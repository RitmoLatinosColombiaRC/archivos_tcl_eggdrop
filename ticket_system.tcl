#######################################################################
# SISTEMA DE TICKETS PARA EGGDROP IRC con ANTIFLOOD
# Versión estable para principiantes
#######################################################################

########################
# CONFIGURACIÓN
########################

set ticket_counter 0
if {![info exists ::botdir]} { set ::botdir [pwd] }
set ticket_dir [file join $::botdir scripts tickets]
set admin_chan "#opers"
set help_chan "#Ayuda"

# CONFIGURACIÓN ANTIFLOOD
# Máximo de comandos permitidos
set flood_max_commands 3  
# Ventana de tiempo en segundos      
set flood_time_window 10    
# Tiempo de silencio en segundos    
set flood_punish_time 60

# Helpers de canales y escritura
proc is_admin_chan {chan} {
    global admin_chan
    return [string equal -nocase $chan $admin_chan]
}
proc is_help_chan {chan} {
    global help_chan
    return [string equal -nocase $chan $help_chan]
}
proc ticket_write_atomic {path data} {
    set tmp "$path.tmp.[pid]"
    if {[catch {set fh [open $tmp w]} err]} {
        putlog "ticket: no se pudo escribir $path: $err"
        return 0
    }
    if {[catch {puts -nonewline $fh $data; close $fh} err]} {
        putlog "ticket: error escribiendo $path: $err"
        catch {file delete $tmp}
        return 0
    }
    if {[catch {file rename -force $tmp $path} err]} {
        putlog "ticket: no se pudo renombrar $path: $err"
        catch {file delete $tmp}
        return 0
    }
    return 1
}
        

# Crear carpeta si no existe
if {![file exists $ticket_dir]} {
    file mkdir $ticket_dir
}

########################
# FUNCIONES ANTIFLOOD
########################

# Inicializar datos de flood
set flood_data [dict create]

# Verificar flood
proc check_flood {nick host} {
    global flood_data flood_max_commands flood_time_window flood_punish_time
    
    set key "${nick}:${host}"
    set current_time [clock seconds]
    
    # Verificar si está castigado
    if {[dict exists $flood_data $key punished]} {
        set punished_until [dict get $flood_data $key punished]
        if {$current_time < $punished_until} {
            set remaining [expr {$punished_until - $current_time}]
            return [list 0 "Estás en silencio por flood. Espera ${remaining} segundos."]
        } else {
            # Limpiar castigo expirado
            dict unset flood_data $key
        }
    }
    
    # Obtener o crear historial de comandos
    if {[dict exists $flood_data $key commands]} {
        set commands [dict get $flood_data $key commands]
    } else {
        set commands [list]
    }
    
    # Limpiar comandos antiguos
    set new_commands [list]
    foreach cmd $commands {
        set cmd_time [lindex $cmd 0]
        if {($current_time - $cmd_time) <= $flood_time_window} {
            lappend new_commands $cmd
        }
    }
    
    # Agregar comando actual
    lappend new_commands [list $current_time [clock format $current_time]]
    
    # Verificar si excede el límite
    if {[llength $new_commands] > $flood_max_commands} {
        set punish_until [expr {$current_time + $flood_punish_time}]
        dict set flood_data $key punished $punish_until
        return [list 0 "Has excedido el límite de comandos. Silenciado por ${flood_punish_time} segundos."]
    }
    
    # Guardar comandos actualizados
    dict set flood_data $key commands $new_commands
    
    return [list 1 "OK"]
}

# Reemplazar la función cleanup_flood_data existente con esta:
proc cleanup_flood_data {min hour day month year} {
    global flood_data
    set current_time [clock seconds]
    set keys [dict keys $flood_data]
    
    foreach key $keys {
        if {[dict exists $flood_data $key punished]} {
            set punish_until [dict get $flood_data $key punished]
            if {$current_time >= $punish_until} {
                dict unset flood_data $key
                continue
            }
        }
        if {[dict exists $flood_data $key commands]} {
            set commands [dict get $flood_data $key commands]
            set new_commands [list]
            foreach cmd $commands {
                set cmd_time [lindex $cmd 0]
                if {($current_time - $cmd_time) <= 300} {
                    lappend new_commands $cmd
                }
            }
            if {[llength $new_commands] > 0} {
                dict set flood_data $key commands $new_commands
            } else {
                dict unset flood_data $key
            }
        }
    }
}

# Reemplazar el bind time de cleanup_old_tickets:
# Y eliminar la función auto_cleanup_tickets o dejarla pero corregida:

########################
# FUNCIONES INTERNAS
########################

# Cargar contador (maximo existente + contador, sin colisiones)
proc load_ticket_counter {} {
    global ticket_counter ticket_dir

    set maxid 0
    foreach f [glob -nocomplain "$ticket_dir/ticket_*.txt"] {
        if {[regexp {ticket_(\d+)\.txt} $f -> n]} {
            if {$n > $maxid} { set maxid $n }
        }
    }

    set value $maxid
    set file "$ticket_dir/counter.txt"
    if {[file exists $file]} {
        if {![catch {set fid [open $file r]} err]} {
            set raw [string trim [gets $fid]]
            close $fid
            if {[string is integer -strict $raw] && $raw > $value} {
                set value $raw
            }
        } else {
            putlog "ticket: no se pudo leer $file: $err"
        }
    }

    set ticket_counter $value
    save_ticket_counter
}

# Guardar contador (atomico)
proc save_ticket_counter {} {
    global ticket_counter ticket_dir
    ticket_write_atomic "$ticket_dir/counter.txt" "$ticket_counter\n"
}

# Crear nuevo ID (sin colisiones)
proc ticket_valid_id {id} {
    return [regexp {^[A-Za-z0-9]{1,12}$} $id]
}

proc generate_ticket_id {} {
    set chars "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    set len [string length $chars]
    for {set i 0} {$i < 100} {incr i} {
        set id ""
        for {set j 0} {$j < 6} {incr j} {
            append id [string index $chars [expr {int(rand() * $len)}]]
        }
        if {![ticket_exists $id]} { return $id }
    }
    return "T[clock seconds]"
}

# Verificar si existe
proc ticket_exists {id} {
    global ticket_dir
    return [file exists "$ticket_dir/ticket_$id.txt"]
}

# Leer ticket (con manejo de errores)
proc read_ticket {id} {
    global ticket_dir

    set file "$ticket_dir/ticket_$id.txt"
    if {![file exists $file]} { return "" }
    if {[catch {set fid [open $file r]} err]} {
        putlog "ticket: no se pudo leer $file: $err"
        return ""
    }
    set content [read $fid]
    close $fid
    return $content
}

# Crear ticket (atomico)
proc save_ticket {id nick user host question} {
    global ticket_dir

    set time [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
    set data "TICKET # $id\n==============\nFecha: $time\nUsuario: $nick!$user@$host\nEstado: ABIERTO\nPregunta: $question\n\n--- Historial ---\n$time - Ticket creado por $nick\n"

    if {![ticket_write_atomic "$ticket_dir/ticket_$id.txt" $data]} {
        putlog "ticket: no se pudo guardar el ticket # $id"
        return 0
    }
    return 1
}

# Agregar comentario (atomico)
proc add_ticket_comment {id nick text} {
    global ticket_dir

    set file "$ticket_dir/ticket_$id.txt"
    if {![file exists $file]} { return 0 }

    set time [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
    set content [read_ticket $id]
    append content "$time - $nick: $text\n"
    return [ticket_write_atomic $file $content]
}

# Cambiar estado
proc set_ticket_status {id status nick} {
    global ticket_dir

    set file "$ticket_dir/ticket_$id.txt"
    if {![file exists $file]} { return 0 }

    set content [read_ticket $id]

    if {[regexp -line {^Estado:\s*.*$} $content match_line]} {
        regsub -line {^Estado:\s*.*$} $content "Estado: $status" new_content
    } else {
        set new_content "Estado: $status\n$content"
    }

    if {$new_content eq ""} { set new_content "Estado: $status" }

    if {![ticket_write_atomic $file $new_content]} { return 0 }

    add_ticket_comment $id $nick "Estado cambiado a: $status"
    return 1
}

########################
# COMANDOS USUARIOS (CON ANTIFLOOD)
########################

bind msg - !ayuda msg_create_ticket
proc msg_create_ticket {nick uhost hand text} {
    global admin_chan

    set user [lindex [split $uhost @] 0]
    set host [lindex [split $uhost @] 1]

    set flood_check [check_flood $nick $host]

    if {![lindex $flood_check 0]} {
        putserv "PRIVMSG $nick :[lindex $flood_check 1]"
        return 0
    }

    if {[string trim $text] eq ""} {
        putserv "PRIVMSG $nick :Uso: /msg $::botnick ayuda <pregunta>"
        return 0
    }

    set id [generate_ticket_id]
    if {![save_ticket $id $nick $user $host $text]} {
        putserv "PRIVMSG $nick :No se pudo crear el ticket, intenta de nuevo."
        return 0
    }

    putserv "PRIVMSG $nick :Tu ticket # $id fue creado correctamente."
    putserv "PRIVMSG $admin_chan :Nuevo ticket # $id creado por $nick."

    return 1
}


# =========================================================
# ESTADO DETALLADO Y AVISOS DE ATENCION
# =========================================================

proc ticket_history_lines {content} {
    set marker "--- Historial ---"
    set idx [string first $marker $content]
    if {$idx < 0} { return [list] }
    set hist [string range $content [expr {$idx + [string length $marker]}] end]
    set lines [list]
    foreach line [split $hist "\n"] {
        set line [string trim $line]
        if {$line ne ""} { lappend lines $line }
    }
    return $lines
}

proc ticket_last_reason {content} {
    set lines [ticket_history_lines $content]
    foreach line [lreverse $lines] {
        if {[regexp {Cerrado automaticamente:\s*(.+)$} $line -> reason]} {
            return [string trimright $reason "."]
        }
        if {[regexp -- {-\s+([^:]+):\s+Estado cambiado a:\s*CERRADO} $line -> who]} {
            return "cerrado por $who"
        }
        if {[regexp {Respuesta:} $line]} {
            return "tiene respuesta de un operador"
        }
    }
    return ""
}

proc ticket_status_notice_due {id} {
    global ticket_status_notices
    if {![info exists ticket_status_notices]} { set ticket_status_notices [dict create] }
    set now [clock seconds]
    if {[dict exists $ticket_status_notices $id]} {
        if {($now - [dict get $ticket_status_notices $id]) < 600} { return 0 }
    }
    return 1
}

proc ticket_status_notice_mark {id} {
    global ticket_status_notices
    if {![info exists ticket_status_notices]} { set ticket_status_notices [dict create] }
    dict set ticket_status_notices $id [clock seconds]
}

bind msg - !estado msg_check_status
proc msg_check_status {nick uhost hand text} {
    global admin_chan

    set id [string toupper [string trim $text]]

    if {$id eq ""} {
        putserv "PRIVMSG $nick :Uso: /msg $::botnick estado <id>"
        return 0
    }
    if {![ticket_valid_id $id]} {
        putserv "PRIVMSG $nick :ID invalido (debe ser alfanumerico)"
        return 0
    }

    set content [read_ticket $id]
    if {$content eq ""} {
        putserv "PRIVMSG $nick :Ticket no encontrado"
        return 0
    }

    set status "DESCONOCIDO"
    if {[regexp {Estado:\s*([^\n\r]+)} $content -> st]} {
        set status [string trim $st]
    }
    set reason [ticket_last_reason $content]
    set msg "Ticket # $id -> Estado: $status."

    switch -- $status {
        "ABIERTO" {
            append msg " Un operador lo atendera pronto; si tarda, avisaremos en #opers."
        }
        "EN PROCESO" {
            if {[string first "Respuesta:" $content] >= 0} {
                append msg " Ya tiene respuesta de un operador; espera la atencion."
            } else {
                append msg " Aun no tiene respuesta; espera a ser atendido. Avisaremos en #opers."
            }
        }
        "EN ESPERA" {
            set d [ticket_pending_read $id]
            set rem 300
            if {[dict exists $d time]} {
                set rem [expr {300 - ([clock seconds] - [dict get $d time])}]
                if {$rem < 0} { set rem 0 }
            }
            if {$rem <= 0} {
                append msg " El plazo de espera ya expiro; el ticket se cerrara en breve."
            } else {
                set mins [expr {($rem + 59) / 60}]
                append msg " El usuario no estaba conectado. Conectate antes de $mins minuto(s) o se cerrara automaticamente."
            }
        }
        "CERRADO" {
            if {$reason ne ""} {
                append msg " Motivo: $reason."
            } else {
                append msg " Motivo: cerrado por un operador."
            }
        }
        default {
            append msg " Estado no reconocido."
        }
    }

    putserv "PRIVMSG $nick :$msg"

    # Aviso a #opers solo si sigue sin atencion (ABIERTO o EN PROCESO sin respuesta)
    if {($status eq "ABIERTO") || ($status eq "EN PROCESO" && [string first "Respuesta:" $content] < 0)} {
        if {[ticket_status_notice_due $id]} {
            set unick "desconocido"
            if {[regexp {Usuario:\s*([^!\s]+)} $content -> un]} { set unick $un }
            putserv "PRIVMSG $admin_chan :Aviso: ticket # $id ($status) de $unick sigue sin atencion."
            ticket_status_notice_mark $id
        }
    }

    return 1
}


# =========================================================
# APELACION DE TICKETS (reconexion con otro nick)
# =========================================================

proc ticket_set_owner {id nick user host} {
    global ticket_dir
    set file "$ticket_dir/ticket_$id.txt"
    if {![file exists $file]} { return 0 }
    set content [read_ticket $id]
    if {[regexp -line {^Usuario:.*$} $content]} {
        regsub -line {^Usuario:.*$} $content "Usuario: $nick!$user@$host" newc
    } else {
        set newc "Usuario: $nick!$user@$host\n$content"
    }
    return [ticket_write_atomic $file $newc]
}

proc pub_apelar_ticket {nick uhost hand chan text} {
    msg_apelar_ticket $nick $uhost $hand $text
}

bind msg - !apelar msg_apelar_ticket
proc msg_apelar_ticket {nick uhost hand text} {
    global admin_chan

    set parts [split [string trim $text]]
    set id [string toupper [lindex $parts 0]]
    set keyword [join [lrange $parts 1 end] " "]

    if {$id eq "" || ![ticket_valid_id $id]} {
        putserv "PRIVMSG $nick :Uso: !apelar <id> \[palabra clave de tu pregunta\]"
        return 0
    }

    if {![ticket_exists $id]} {
        putserv "PRIVMSG $nick :Ticket # $id no encontrado"
        return 0
    }

    set content [read_ticket $id]
    if {![regexp {Usuario:\s*([^!\s]+)!([^@\s]+)@([^\n\r\s]+)} $content -> oldnick olduser oldhost]} {
        putserv "PRIVMSG $nick :No se pudo leer el propietario del ticket # $id."
        return 0
    }

    set question ""
    if {[regexp {Pregunta:\s*([^\n\r]+)} $content -> q]} { set question $q }

    set hostmatch 0
    if {$uhost eq "$olduser@$oldhost"} { set hostmatch 1 }
    if {[string match "*@$oldhost" $uhost]} { set hostmatch 1 }

    set keyword [string trim $keyword]
    set kwmatch 0
    if {[string length $keyword] >= 4 && $question ne ""} {
        if {[string first [string tolower $keyword] [string tolower $question]] >= 0} {
            set kwmatch 1
        }
    }

    if {!$hostmatch && !$kwmatch} {
        putserv "PRIVMSG $nick :No pude validar el ticket # $id desde este host. Usa una palabra clave de tu pregunta: !apelar $id <palabra>."
        return 0
    }

    set user [lindex [split $uhost @] 0]
    set host [lindex [split $uhost @] 1]
    if {![ticket_set_owner $id $nick $user $host]} {
        putserv "PRIVMSG $nick :No se pudo actualizar el propietario del ticket # $id."
        return 0
    }

    set how [expr {$hostmatch ? "hostmask" : "palabra clave"}]
    add_ticket_comment $id $nick "Apelacion: reclamo el ticket (validado por $how)."

    set status ""
    regexp {Estado:\s*([^\n\r]+)} $content -> status
    set status [string trim $status]

    if {$status eq "CERRADO"} {
        set_ticket_status $id "EN PROCESO" $nick
        add_ticket_comment $id "Sistema" "Ticket reabierto por apelacion."
    } elseif {$status eq "EN ESPERA"} {
        if {[dict size [ticket_pending_read $id]] > 0} {
            ticket_pending_deliver $id $nick
        } else {
            set_ticket_status $id "EN PROCESO" $nick
        }
    } elseif {$status eq "ABIERTO"} {
        set_ticket_status $id "EN PROCESO" $nick
    }

    putserv "PRIVMSG $nick :Ticket # $id reclamado. Ahora estas asociado como $nick."
    putserv "PRIVMSG $admin_chan :Apelacion: ticket # $id reclamado por $nick (validado por $how)."
    return 1
}

bind pub - !apelar pub_apelar_ticket

########################
# COMANDOS OPERADORES (SIN ANTIFLOOD PARA OPERADORES)
########################

bind pub - !tomar pub_take_ticket
proc pub_take_ticket {nick uhost hand chan text} {
    global admin_chan

    if {![is_admin_chan $chan]} { return 0 }

    set id [string toupper [string trim $text]]

    # Validaciones
    if {$id eq ""} {
        putserv "PRIVMSG $admin_chan :Uso: !tomar <id>"
        return 0
    }

    if {![ticket_valid_id $id]} {
        putserv "PRIVMSG $admin_chan :ID invalido (debe ser alfanumerico)"
        return 0
    }

    if {![ticket_exists $id]} {
        putserv "PRIVMSG $admin_chan :Ticket # $id no existe"
        return 0
    }

    set_ticket_status $id "EN PROCESO" $nick

    putserv "PRIVMSG $admin_chan :Ticket # $id tomado por $nick"

    # enviar aviso privado al usuario
    set content [read_ticket $id]

    if {[regexp {Usuario: ([^!]+)} $content -> usernick]} {
        putserv "PRIVMSG $usernick :Tu ticket # $id esta siendo atendido por $nick."
    }

    return 1
}


# =========================================================
# RESPUESTAS PENDIENTES (usuario no conectado)
# =========================================================

proc ticket_pending_file {id} {
    global ticket_dir
    return "$ticket_dir/pending_$id.txt"
}

proc ticket_pending_write {id nick userhost operator message} {
    set file [ticket_pending_file $id]
    set data "id: $id\nnick: $nick\nuserhost: $userhost\noperator: $operator\ntime: [clock seconds]\nmessage: $message\n"
    return [ticket_write_atomic $file $data]
}

proc ticket_pending_read {id} {
    set d [dict create]
    set file [ticket_pending_file $id]
    if {![file exists $file]} { return $d }
    if {[catch {set fid [open $file r]} err]} {
        putlog "ticket: no se pudo leer $file: $err"
        return $d
    }
    set content [read $fid]
    close $fid
    foreach line [split $content "\n"] {
        if {[regexp {^([^:]+):\s*(.*)$} $line -> k v]} {
            dict set d $k $v
        }
    }
    return $d
}

proc ticket_pending_del {id} {
    catch {file delete [ticket_pending_file $id]}
}

proc ticket_pending_deliver {id {tonick ""}} {
    global admin_chan
    set d [ticket_pending_read $id]
    if {[dict size $d] == 0} { return 0 }
    set pnick [dict get $d nick]
    set msg [dict get $d message]
    if {$tonick eq ""} { set tonick $pnick }
    putserv "PRIVMSG $tonick :Respuesta a ticket # $id: $msg"
    add_ticket_comment $id "Sistema" "Respuesta entregada al conectar ($tonick)."
    set_ticket_status $id "EN PROCESO" "Sistema"
    ticket_pending_del $id
    putserv "PRIVMSG $admin_chan :Ticket # $id: respuesta entregada a $tonick al conectarse."
    return 1
}

proc ticket_pending_timeout {id} {
    global admin_chan
    set d [ticket_pending_read $id]
    if {[dict size $d] == 0} { return }
    set pnick [dict get $d nick]
    set when 0
    if {[dict exists $d time]} { set when [dict get $d time] }

    if {[onchan $pnick]} {
        ticket_pending_deliver $id $pnick
        return
    }

    set age [expr {[clock seconds] - $when}]
    if {$age < 300} {
        utimer [expr {300 - $age}] [list ticket_pending_timeout $id]
        return
    }

    set_ticket_status $id "CERRADO" "Sistema"
    add_ticket_comment $id "Sistema" "Cerrado automaticamente: el usuario no se conecto en 5 minutos."
    ticket_pending_del $id
    putserv "PRIVMSG $admin_chan :Ticket # $id cerrado automaticamente: $pnick no se conecto en 5 minutos."
}

proc ticket_pending_join {nick uhost hand chan} {
    global ticket_dir
    foreach f [glob -nocomplain "$ticket_dir/pending_*.txt"] {
        if {![regexp {pending_([A-Za-z0-9]+)\.txt} $f -> id]} { continue }
        set d [ticket_pending_read $id]
        if {[dict size $d] == 0} { continue }
        set pnick [dict get $d nick]
        set puh ""
        if {[dict exists $d userhost]} { set puh [dict get $d userhost] }
        if {($pnick eq $nick) || ($puh ne "" && $puh eq $uhost)} {
            ticket_pending_deliver $id $nick
        }
    }
}

proc ticket_pending_resume {} {
    global ticket_dir
    foreach f [glob -nocomplain "$ticket_dir/pending_*.txt"] {
        if {![regexp {pending_([A-Za-z0-9]+)\.txt} $f -> id]} { continue }
        set d [ticket_pending_read $id]
        if {[dict size $d] == 0} { continue }
        set when 0
        if {[dict exists $d time]} { set when [dict get $d time] }
        set age [expr {[clock seconds] - $when}]
        if {$age >= 300} {
            ticket_pending_timeout $id
        } else {
            utimer [expr {300 - $age}] [list ticket_pending_timeout $id]
        }
    }
}

bind pub - !responder pub_respond_ticket
proc pub_respond_ticket {nick uhost hand chan text} {
    global admin_chan help_chan

    if {![is_admin_chan $chan]} { return 0 }

    set id [string toupper [lindex $text 0]]
    set msg [join [lrange $text 1 end] " "]

    if {$id eq ""} {
        putserv "PRIVMSG $admin_chan :Uso: !responder <id> <mensaje>"
        return 0
    }
    if {![ticket_valid_id $id]} {
        putserv "PRIVMSG $admin_chan :ID invalido (debe ser alfanumerico)"
        return 0
    }
    if {$msg eq ""} {
        putserv "PRIVMSG $admin_chan :Uso: !responder <id> <mensaje>"
        return 0
    }
    if {[string length $msg] > 400} {
        putserv "PRIVMSG $admin_chan :Respuesta demasiado larga (max 400 caracteres)"
        return 0
    }
    if {![ticket_exists $id]} {
        putserv "PRIVMSG $admin_chan :Ticket # $id no existe"
        return 0
    }

    set content [read_ticket $id]
    set status ""
    if {[regexp {Estado:\s*([^\n\r]+)} $content -> status]} {
        if {$status eq "CERRADO"} {
            putserv "PRIVMSG $admin_chan :Ticket # $id esta CERRADO, no se puede responder."
            return 0
        }
        if {$status eq "ABIERTO"} {
            set_ticket_status $id "EN PROCESO" $nick
            putserv "PRIVMSG $admin_chan :Ticket # $id cambiado a EN PROCESO automaticamente."
        }
    }

    if {[regexp {Usuario:\s*([^!\s]+)!([^@\s]+)@([^\n\r\s]+)} $content -> usernick ident host]} {
        add_ticket_comment $id $nick "Respuesta: $msg"

        if {[onchan $usernick]} {
            ticket_pending_del $id
            putserv "PRIVMSG $usernick :Respuesta a ticket # $id: $msg"
            putserv "PRIVMSG $admin_chan :Respuesta enviada a $usernick por ticket # $id"
            if {$status eq "EN ESPERA"} { set_ticket_status $id "EN PROCESO" $nick }
        } else {
            ticket_pending_write $id $usernick "$ident@$host" $nick $msg
            set_ticket_status $id "EN ESPERA" $nick
            putserv "PRIVMSG $admin_chan :Ticket # $id en espera: $usernick no esta conectado. Se cerrara en 5 minutos si no aparece."
            utimer 300 [list ticket_pending_timeout $id]
        }
    } else {
        if {[regexp {Usuario:\s+(\S+)} $content -> usernick]} {
            add_ticket_comment $id $nick "Respuesta: $msg"
            if {[onchan $usernick]} {
                ticket_pending_del $id
                putserv "PRIVMSG $usernick :Respuesta a ticket # $id: $msg"
                putserv "PRIVMSG $admin_chan :Respuesta enviada a $usernick por ticket # $id"
            } else {
                ticket_pending_write $id $usernick "" $nick $msg
                set_ticket_status $id "EN ESPERA" $nick
                putserv "PRIVMSG $admin_chan :Ticket # $id en espera: $usernick no esta conectado. Se cerrara en 5 minutos si no aparece."
                utimer 300 [list ticket_pending_timeout $id]
            }
        } else {
            putserv "PRIVMSG $admin_chan :No se pudo identificar el usuario del ticket # $id"
            return 0
        }
    }

    return 1
}

bind pub - !cerrar pub_close_ticket
proc pub_close_ticket {nick uhost hand chan text} {
    global admin_chan help_chan

    if {![is_admin_chan $chan]} { return 0 }

    set id [string toupper [string trim $text]]

    # Validaciones
    if {$id eq ""} {
        putserv "PRIVMSG $admin_chan :Uso: !cerrar <id>"
        return 0
    }

    if {![ticket_valid_id $id]} {
        putserv "PRIVMSG $admin_chan :ID invalido (debe ser alfanumerico)"
        return 0
    }

    if {![ticket_exists $id]} {
        putserv "PRIVMSG $admin_chan :Ticket # $id no existe"
        return 0
    }

    set content [read_ticket $id]

    set_ticket_status $id "CERRADO" $nick
    ticket_pending_del $id

    if {[regexp {Usuario: ([^!]+)!([^@]+)@([^\n\r]+)} $content -> usernick ident userhost]} {
		putserv "PRIVMSG $usernick :Tu ticket # $id fue cerrado, por favor abandona el canal #Ayuda gracias..."

		# ban + kick después de 30 segundos
		set banhost [lindex [split $userhost @] 1]
		if {$banhost eq ""} { set banhost $userhost }
		utimer 30 [list putserv "MODE $help_chan +b *!*@$banhost"]
		utimer 30 [list putserv "KICK $help_chan $usernick :No puedes permanecer en el canal $help_chan, tu ticket ha sido cerrado gracias por visitarnos..."]
	}
    
    putserv "PRIVMSG $admin_chan :Ticket # $id cerrado por $nick"
	

    return 1
}

bind pub - !ticket pub_view_ticket
proc pub_view_ticket {nick uhost hand chan text} {
    global admin_chan

    if {![is_admin_chan $chan]} { return 0 }

    set id [string toupper [string trim $text]]
    
    if {$id eq ""} {
        putserv "PRIVMSG $admin_chan :Uso: !ticket <id>"
        return 0
    }
    
    if {![ticket_valid_id $id]} {
        putserv "PRIVMSG $admin_chan :ID invalido (debe ser alfanumerico)"
        return 0
    }
    
    set content [read_ticket $id]

    if {$content eq ""} {
        putserv "PRIVMSG $admin_chan :Ticket # $id no encontrado"
        return 0
    }

    putserv "PRIVMSG $admin_chan :=== TICKET # $id ==="
    
    # Mostrar TODO sin límite
    foreach line [split $content "\n"] {
        if {$line ne ""} {
            set line [regsub {^TICKET #([A-Za-z0-9])} $line {TICKET # \1}]
            putserv "PRIVMSG $admin_chan :$line"
        }
    }
    
    putserv "PRIVMSG $admin_chan :=== FIN TICKET # $id ==="

    return 1
}

bind pub - !tickets pub_list_tickets
proc pub_list_tickets {nick uhost hand chan text} {
    global admin_chan ticket_dir

    if {![is_admin_chan $chan]} { return 0 }

    set files [glob -nocomplain "$ticket_dir/ticket_*.txt"]
    
    # Lista para almacenar tickets activos
    set active_tickets [list]
    
    # Recorrer todos los tickets y filtrar por estado
    foreach file $files {
        if {[regexp {ticket_([A-Za-z0-9]+)\.txt} $file -> num]} {
            set content [read_ticket $num]
            if {$content ne ""} {
                # Extraer el estado del ticket
                if {[regexp {Estado:\s*([^\n\r]+)} $content -> status]} {
                    # Solo incluir tickets ABIERTOS o EN PROCESO
                    if {$status eq "ABIERTO" || $status eq "EN PROCESO" || $status eq "EN ESPERA"} {
                        lappend active_tickets [list $num $status]
                    }
                }
            }
        }
    }
    
    # Limitar a 10 tickets por vez para evitar flood
    set max_display 10
    set count 0
    set total [llength $active_tickets]

    if {$total == 0} {
        putserv "PRIVMSG $admin_chan :No hay tickets activos (ABIERTO o EN PROCESO)"
        return 0
    }

    putserv "PRIVMSG $admin_chan :=== TICKETS ACTIVOS ($total totales) ==="
    
    # Ordenar tickets por ID (los más recientes primero)
    set active_tickets [lsort -decreasing -index 0 $active_tickets]
    
    foreach ticket $active_tickets {
        if {$count < $max_display} {
            set num [lindex $ticket 0]
            set status [lindex $ticket 1]
            putserv "PRIVMSG $admin_chan :Ticket # $num - Estado: $status"
            incr count
        }
    }
    
    if {$total > $max_display} {
        putserv "PRIVMSG $admin_chan :... y [expr {$total - $max_display}] tickets activos mas"
    }

    return 1
}

bind pub - !ticketsall pub_list_all_tickets
proc pub_list_all_tickets {nick uhost hand chan text} {
    global admin_chan ticket_dir

    if {![is_admin_chan $chan]} { return 0 }

    set files [glob -nocomplain "$ticket_dir/ticket_*.txt"]
    
    set all_tickets [list]
    set closed_tickets [list]
    
    foreach file $files {
        if {[regexp {ticket_([A-Za-z0-9]+)\.txt} $file -> num]} {
            set content [read_ticket $num]
            if {$content ne ""} {
                if {[regexp {Estado:\s*([^\n\r]+)} $content -> status]} {
                    if {$status eq "CERRADO"} {
                        lappend closed_tickets $num
                    } else {
                        lappend all_tickets $num
                    }
                }
            }
        }
    }
    
    set total_active [llength $all_tickets]
    set total_closed [llength $closed_tickets]
    
    putserv "PRIVMSG $admin_chan :=== RESUMEN DE TICKETS ==="
    putserv "PRIVMSG $admin_chan :Activos (ABIERTO/EN PROCESO): $total_active"
    putserv "PRIVMSG $admin_chan :Cerrados: $total_closed"
    putserv "PRIVMSG $admin_chan :Total: [expr {$total_active + $total_closed}]"
    
    if {$total_active > 0} {
        putserv "PRIVMSG $admin_chan :=== TICKETS ACTIVOS ==="
        set sorted_active [lsort -decreasing $all_tickets]
        set count 0
        foreach num $sorted_active {
            if {$count < 10} {
                set content [read_ticket $num]
                if {[regexp {Estado:\s*([^\n\r]+)} $content -> status]} {
                    putserv "PRIVMSG $admin_chan :Ticket # $num - Estado: $status"
                }
                incr count
            }
        }
        if {$total_active > 10} {
            putserv "PRIVMSG $admin_chan :... y [expr {$total_active - 10}] mas"
        }
    }
    
    return 1
}

########################
# LIMPIEZA AUTOMÁTICA
########################

proc cleanup_old_tickets {} {
    global ticket_dir

    set now [clock seconds]
    set max_age [expr {15 * 24 * 60 * 60}]  # 15 días

    set files [glob -nocomplain "$ticket_dir/ticket_*.txt"]

    foreach file $files {
        if {[catch {open $file r} fid]} {
            continue
        }

        set content [read $fid]
        close $fid

        if {[string match "*Estado: CERRADO*" $content]} {
            set age [expr {$now - [file mtime $file]}]

            if {$age > $max_age} {
                catch {file delete $file}
                putlog "Ticket eliminado: $file"
            }
        }
    }
}

bind time - "* * * * *" cleanup_flood_data
bind time - "00 03 * * *" auto_cleanup_tickets
proc auto_cleanup_tickets {min hour day month year} {
    cleanup_old_tickets
}

########################
# AYUDA DEL SISTEMA
########################

bind pub - !help_ticket pub_help_ticket
bind msg - !help_ticket msg_help_ticket

proc pub_help_ticket {nick uhost hand chan text} {
    if {[is_admin_chan $chan]} {
        help_ticket_core $nick $chan
    } else {
        help_ticket_core $nick "PRIVATE"
    }
    return 1
}

proc msg_help_ticket {nick uhost hand text} {
    help_ticket_core $nick "PRIVATE"
    return 1
}

proc help_ticket_core {nick source} {
    global admin_chan

    # Si viene por privado
    if {$source eq "PRIVATE"} {
        putserv "PRIVMSG $nick :=== AYUDA DEL SISTEMA DE TICKETS ==="
        putserv "PRIVMSG $nick :!ayuda <pregunta> -> Crear un ticket nuevo"
        putserv "PRIVMSG $nick :!estado <id> -> Consultar estado de tu ticket"
        putserv "PRIVMSG $nick :!apelar <id> \[palabra\] -> Reclamar un ticket si cambiaste de nick."
        putserv "PRIVMSG $nick :help_ticket -> Mostrar esta ayuda"
        return
    }

    # Si viene desde #opers
    if {[string equal -nocase $source $admin_chan]} {
        putserv "PRIVMSG $admin_chan :$nick: === COMANDOS DE OPERADOR ==="
        putserv "PRIVMSG $admin_chan :!tomar <id> -> Tomar ticket"
        putserv "PRIVMSG $admin_chan :!responder <id> <mensaje> -> Responder ticket"
        putserv "PRIVMSG $admin_chan :!cerrar <id> -> Cerrar ticket"
        putserv "PRIVMSG $admin_chan :!ticket <id> -> Ver ticket completo"
        putserv "PRIVMSG $admin_chan :!tickets -> Listar tickets activos"
        putserv "PRIVMSG $admin_chan :!ticketsall -> Resumen de todos los tickets"
        return
    }
}

# Comando para ver configuración de flood (solo operadores)
bind pub - !flood_config pub_flood_config
proc pub_flood_config {nick uhost hand chan text} {
    global admin_chan flood_max_commands flood_time_window flood_punish_time
    
    if {![is_admin_chan $chan]} { return 0 }
    
    putserv "PRIVMSG $admin_chan :=== CONFIGURACION ANTIFLOOD ==="
    putserv "PRIVMSG $admin_chan :Max comandos: $flood_max_commands"
    putserv "PRIVMSG $admin_chan :Ventana tiempo: $flood_time_window segundos"
    putserv "PRIVMSG $admin_chan :Tiempo castigo: $flood_punish_time segundos"
    
    return 1
}


########################
# CONTADOR DE VISITAS DEL CANAL #Ayuda
########################

set visitas_canal_file "$ticket_dir/visitas_canal.txt"
set total_visitas_canal 0
set usuarios_conectados [dict create]

# Cargar contador de visitas
proc load_visitas_canal {} {
    global visitas_canal_file total_visitas_canal

    set total_visitas_canal 0
    if {[file exists $visitas_canal_file]} {
        if {![catch {set fid [open $visitas_canal_file r]} err]} {
            set content [read $fid]
            close $fid
            if {[regexp {TotalVisitas:\s*(\d+)} $content -> total]} {
                set total_visitas_canal $total
            }
        } else {
            putlog "ticket: no se pudo leer $visitas_canal_file: $err"
        }
    }
}

# Guardar contador de visitas
proc save_visitas_canal {} {
    global visitas_canal_file total_visitas_canal
    set data "TotalVisitas: $total_visitas_canal\nUltimaActualizacion: [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]\n"
    ticket_write_atomic $visitas_canal_file $data
}

# Incrementar contador de visitas
proc increment_visitas_canal {} {
    global total_visitas_canal
    incr total_visitas_canal
    save_visitas_canal
}

# Inicializar la lista de usuarios conectados
proc init_usuarios_conectados {} {
    global help_chan usuarios_conectados

    # Verificar que el canal exista en la memoria de Eggdrop
    if {![validchan $help_chan]} {
        putlog "INFO: Canal $help_chan aun no disponible, omitiendo inicializacion."
        return
    }

    # Obtener usuarios del canal
    if {[catch {set usuarios [chanlist $help_chan]} error]} {
        putlog "ERROR obteniendo usuarios de $help_chan: $error"
        return
    }

    foreach usuario $usuarios {
        set uhost [getchanhost $usuario $help_chan]
        if {$uhost eq ""} { set uhost "*" }
        set clave "${usuario}!${uhost}"

        if {![dict exists $usuarios_conectados $clave]} {
            dict set usuarios_conectados $clave [clock seconds]
        }
    }

    set total [dict size $usuarios_conectados]
    putlog "Inicializados $total usuarios conectados en $help_chan"
}

# Detectar cuando un usuario entra al canal #Ayuda
bind join - "#Ayuda *" on_join_ayuda
bind join - * ticket_pending_join
proc on_join_ayuda {nick uhost hand chan} {
    global help_chan total_visitas_canal usuarios_conectados admin_chan
    
    if {![is_help_chan $chan]} { return 0 }
    
    set clave "${nick}!${uhost}"
    
    # Verificar si es la primera vez que entra este usuario en esta sesión
    if {![dict exists $usuarios_conectados $clave]} {
        dict set usuarios_conectados $clave [clock seconds]
        increment_visitas_canal
        
        # Mostrar mensaje de bienvenida
        putserv "PRIVMSG $nick :Bienvenido $nick al canal #Ayuda, para crear un TICKET escribe !ayuda <Mensaje>."
		putserv "PRIVMSG $nick :Si necesitas ver el estado de tu ticket escribe !estado <Número de ticket>."
        putserv "PRIVMSG $admin_chan :[clock format [clock seconds] -format "%H:%M:%S"] - $nick ha entrado a #Ayuda (Visita #$total_visitas_canal)"
    }
    
    return 1
}

# Detectar cuando un usuario sale del canal #Ayuda
bind part - "#Ayuda *" on_part_ayuda
proc on_part_ayuda {nick uhost hand chan msg} {
    global help_chan usuarios_conectados admin_chan
    
    if {![is_help_chan $chan]} { return 0 }
    
    set clave "${nick}!${uhost}"
    
    if {[dict exists $usuarios_conectados $clave]} {
        dict unset usuarios_conectados $clave
        putserv "PRIVMSG $admin_chan :[clock format [clock seconds] -format "%H:%M:%S"] - $nick ha salido de #Ayuda"
    }
    
    return 1
}

# Detectar cuando un usuario se desconecta (QUIT)
bind sign - * on_sign_ayuda

proc on_sign_ayuda {nick uhost hand chan reason} {
    global usuarios_conectados admin_chan

    set clave "${nick}!${uhost}"

    if {[dict exists $usuarios_conectados $clave]} {
        dict unset usuarios_conectados $clave
        putserv "PRIVMSG $admin_chan :[clock format [clock seconds] -format "%H:%M:%S"] - $nick se ha desconectado de #Ayuda"
    }

    return 1
}

# Comando para ver estadísticas de visitas (en #opers)
bind pub - !visitas pub_show_visitas_canal
proc pub_show_visitas_canal {nick uhost hand chan text} {
    global admin_chan total_visitas_canal usuarios_conectados help_chan
    
    if {![is_admin_chan $chan]} { return 0 }
    if {![validchan $help_chan]} {
    putserv "PRIVMSG $admin_chan :El canal $help_chan no esta disponible."
    return 0
}
    # Actualizar lista de usuarios (por si acaso)
    set usuarios_actuales [chanlist $help_chan]
    set conectados_ahora [llength $usuarios_actuales]
    
    putserv "PRIVMSG $admin_chan :=== ESTADISTICAS DEL CANAL #Ayuda ==="
    putserv "PRIVMSG $admin_chan :Visitas totales (desde que se creo el contador): $total_visitas_canal"
    putserv "PRIVMSG $admin_chan :Usuarios conectados ahora: $conectados_ahora"
    putserv "PRIVMSG $admin_chan :========================================="
    
    return 1
}

# Comando para ver lista de usuarios conectados (en #opers)
bind pub - !conectados pub_list_conectados
proc pub_list_conectados {nick uhost hand chan text} {
    global admin_chan usuarios_conectados help_chan
    
    if {![is_admin_chan $chan]} { return 0 }
    if {![validchan $help_chan]} {
    putserv "PRIVMSG $admin_chan :El canal $help_chan no esta disponible."
    return 0
}
    # Obtener lista actual de usuarios en el canal
    set usuarios_actuales [chanlist $help_chan]
    set conectados [llength $usuarios_actuales]
    
    if {$conectados == 0} {
        putserv "PRIVMSG $admin_chan :No hay usuarios conectados en #Ayuda"
        return 0
    }
    
    putserv "PRIVMSG $admin_chan :=== Usuarios conectados en #Ayuda ($conectados) ==="
    
    foreach usuario $usuarios_actuales {
        # Obtener hora de entrada si está registrado
        set hora_entrada "desconocida"
        dict for {clave tiempo} $usuarios_conectados {
            if {[string match "${usuario}!*" $clave]} {
                set hora_entrada [clock format $tiempo -format "%H:%M:%S"]
                break
            }
        }
        putserv "PRIVMSG $admin_chan : - $usuario (desde $hora_entrada)"
    }
    
    putserv "PRIVMSG $admin_chan :========================================="
    
    return 1
}

# Comando para resetear el contador (en #opers)
bind pub - !reset_visitas pub_reset_visitas
proc pub_reset_visitas {nick uhost hand chan text} {
    global admin_chan total_visitas_canal
    
    if {![is_admin_chan $chan]} { return 0 }
    
    set total_visitas_canal 0
    save_visitas_canal
    
    putserv "PRIVMSG $admin_chan :Contador de visitas reiniciado por $nick"
    
    return 1
}

# Inicializar contador y usuarios al cargar el script
# Inicializar contador
load_visitas_canal

# Esperar a que Eggdrop termine de conectar
bind evnt - init-server iniciar_visitas_sistema

proc iniciar_visitas_sistema {type} {
    utimer 20 init_usuarios_conectados
}

putlog "Contador de visitas para #Ayuda cargado - Total actual: $total_visitas_canal"
########################
# INICIO
########################

load_ticket_counter
ticket_pending_resume
putlog "Sistema de tickets cargado correctamente con proteccion antiflood"
putlog "Canales: $help_chan y $admin_chan"
putlog "Configuracion antiflood: $flood_max_commands comandos en $flood_time_window segundos"
# Wrappers para usar !ayuda y !estado tambien en canal
bind pub - !ayuda pub_create_ticket
proc pub_create_ticket {nick uhost hand chan text} {
    msg_create_ticket $nick $uhost $hand $text
}
bind pub - !estado pub_check_status
proc pub_check_status {nick uhost hand chan text} {
    msg_check_status $nick $uhost $hand $text
}
