#------------------------------------------------------------#
#        🎟️ Sistema de Tickets – Ritmo Latinos Colombia      #
#        🚀 VERSIÓN PROFESIONAL CORREGIDA - v2.1            #
#------------------------------------------------------------#
# Autor: Atómico (Founder)
# Versión: 2.1
# Email: r.ritmo.latinos@gmail.com
#
# 📌 Descripción:
# Servicio de ayuda y gestión de tickets para usuarios y operadores.
# REQUIERE validación de licencia previa.
# SISTEMA OPTIMIZADO Y CORREGIDO
#------------------------------------------------------------#

# Verificar que la licencia fue validada antes de continuar
if {![license::is_validated]} {
    puts "❌ ERROR: La licencia no ha sido validada. Cargue primero license_validation.tcl"
    return
}

### =======================
### CONFIGURACIÓN MEJORADA
### =======================
set tickets_file "tickets.txt"
set ticketslog_file "tickets.log"

set support_channel "#ritmolatinos_help" 
set ops_channel     "#ritmolatinos_ad"

array set ticket_timers {
    warn       600
    escalate   1800
    autoclose  3600
}

set ticket_ban_time 300
set max_daily_tickets 5
set max_ticket_wait 600
set akick_time 86400

# Arrays para tracking mejorados
array set pending_reconnects {}
array set flood_limit {}
array set flood_count {}

# Sistema de cache para mejor performance
variable tickets_cache ""
variable cache_timestamp 0
variable file_lock 0

### =======================
### UTILIDADES PROFESIONALES
### =======================
proc read_file {filename} {
    if {![file exists $filename]} { return "" }
    set fp [open $filename r]
    set data [read $fp]
    close $fp
    return $data
}

proc write_file {filename data} {
    set fp [open $filename w]
    puts $fp $data
    close $fp
}

proc putlog {msg} {
    global ticketslog_file
    set fp [open $ticketslog_file a]
    puts $fp "[clock format [clock seconds]] $msg"
    close $fp
}

proc read_file_safe {filename} {
    if {![file exists $filename]} { 
        write_file $filename ""
        return ""
    }
    
    # Verificar que sea un archivo regular
    if {![file isfile $filename]} {
        putlog "ERROR: $filename no es un archivo regular"
        return ""
    }
    
    return [read_file $filename]
}

# Sistema de cache para tickets
proc get_cached_tickets {} {
    global tickets_file tickets_cache cache_timestamp
    
    set current_time [clock seconds]
    if {$current_time - $cache_timestamp < 5 && $tickets_cache ne ""} {
        return $tickets_cache
    }
    
    set tickets_cache [split [read_file_safe $tickets_file] "\n"]
    set cache_timestamp $current_time
    return $tickets_cache
}

# Bloqueo para condiciones de carrera
proc with_ticket_lock {script} {
    global file_lock
    
    # Esperar máximo 5 segundos por el lock
    set start_time [clock seconds]
    while {$file_lock && ([clock seconds] - $start_time < 5)} {
        after 100
    }
    
    if {$file_lock} {
        error "Timeout obteniendo lock para archivo de tickets"
    }
    
    set file_lock 1
    set result [catch {uplevel $script} error options]
    set file_lock 0
    
    if {$result} {
        return -code error $error
    }
    
    return
}

### =======================
### DETECCIÓN OPERADORES Y VOICE
### =======================
proc is_operator {nick chan} {
    if {[matchchanattr $nick $chan o]} { return 1 }
    if {[matchchanattr $nick $chan h]} { return 1 }
    if {[matchchanattr $nick $chan a]} { return 1 }
    if {[matchchanattr $nick $chan q]} { return 1 }
    return 0
}

proc is_voiced {nick chan} {
    return [matchchanattr $nick $chan v]
}

proc is_authorized_op {nick chan} {
    global ops_channel
    if {$chan ne $ops_channel} { return 0 }
    return [is_operator $nick $chan]
}

### =======================
### CONTROL ANTIFLOOD MEJORADO
### =======================
proc check_flood {nick} {
    global flood_limit flood_count
    set now [clock seconds]

    # Limpiar entradas antiguas (> 1 hora)
    if {[array size flood_limit] > 1000} {
        array unset flood_limit
        array unset flood_count
        array set flood_limit {}
        array set flood_count {}
    }

    if {![info exists flood_count($nick)]} {
        set flood_count($nick) 1
        set flood_limit($nick) $now
        return 0
    }

    if {$now - $flood_limit($nick) < 5} {
        incr flood_count($nick)
        if {$flood_count($nick) > 3} {
            return 1
        }
    } else {
        set flood_count($nick) 1
        set flood_limit($nick) $now
    }
    return 0
}

### =======================
### INFORMACIÓN DEL BOT
### =======================
set bot_name "IrcHelp"
set bot_version "2.1"
set bot_author "Atómico (Founder)"
set bot_email "r.ritmo.latinos@gmail.com"
set bot_server "irc.chatdetodos.com"
set bot_web "www.ritmolatinoscrc.com"

proc show_bot_info {} {
    global bot_name bot_version bot_author bot_email bot_server bot_web ops_channel

    if {[catch {
        puts "=============================================="
        puts "$bot_name $bot_version - Sistema de Tickets Cargado"
        puts "Autor: $bot_author"
        puts "Email: $bot_email"
        puts "Servidor: $bot_server"
        puts "Web: $bot_web"
        puts "=============================================="

        putserv "PRIVMSG $ops_channel :ℹ️ $bot_name v$bot_version iniciado correctamente."
        
    } err]} {
        puts "⚠️ Error cargando el script de tickets: $err"
    }
}

### =======================
### AUTO-VOICE PARA USUARIOS
### =======================
proc user_joined {nick uhost hand chan} {
    global support_channel pending_reconnects ops_channel
    
    if {$chan eq $support_channel} {
        # Dar voice si no lo tiene
        if {![is_voiced $nick $chan]} {
            putserv "MODE $support_channel +v $nick"
        }
        
        # Verificar si este usuario tenía tickets en espera de reconexión
        set reconnected_tickets {}
        foreach {t_id waiting_nick} [array get pending_reconnects] {
            if {[string equal -nocase $waiting_nick $nick]} {
                lappend reconnected_tickets $t_id
                unset pending_reconnects($t_id)
            }
        }
        
        if {[llength $reconnected_tickets] > 0} {
            putserv "NOTICE $nick :✅ Bienvenido de vuelta! Tus tickets ([join $reconnected_tickets ,]) han sido reactivados."
            putserv "PRIVMSG $ops_channel :✅ $nick reconectó - tickets [join $reconnected_tickets ,] reactivados."
        } else {
            putserv "NOTICE $nick :✅ Bienvenido a $support_channel! Usa !ticket <mensaje> para solicitar ayuda."
        }
    }
}

bind join - * user_joined

### =======================
### SISTEMA DE RECONEXIÓN MEJORADO
### =======================
proc user_left {nick uhost hand chan reason} {
    global tickets_file support_channel max_ticket_wait ops_channel pending_reconnects
    
    # Verificar licencia antes de ejecutar
    if {![license::is_validated]} {
        return
    }
    
    if {$chan ne $support_channel} { return }
    
    with_ticket_lock {
        set lines [get_cached_tickets]
        set found_assigned_tickets 0
        
        foreach line $lines {
            if {$line eq ""} continue
            set parts [split $line ";"]
            if {[llength $parts] < 5} continue
            
            set t_id [lindex $parts 0]
            set tnick [lindex $parts 1]
            set tasign [lindex $parts 4]
            
            if {[string equal -nocase $tnick $nick] && $tasign ne "-" && $tasign ne ""} {
                # Solo poner en espera tickets que ESTÁN SIENDO ATENDIDOS
                set pending_reconnects($t_id) $nick
                putserv "PRIVMSG $ops_channel :ℹ️ Ticket $t_id de $nick en espera por desconexión. Tiene $max_ticket_wait segundos para reconectar."
                utimer $max_ticket_wait [list check_user_reconnected $t_id $nick]
                set found_assigned_tickets 1
            }
        }
        
        if {!$found_assigned_tickets} {
            # Si el usuario no tenía tickets siendo atendidos, eliminar tickets no asignados
            remove_unassigned_user_tickets $nick
        }
    }
}

proc check_user_reconnected {t_id nick} {
    global pending_reconnects tickets_file ops_channel support_channel
    
    if {![info exists pending_reconnects($t_id)]} {
        return  # Ya fue manejado
    }
    
    # Verificación robusta de presencia en canal
    set is_present 0
    if {[catch {set is_present [onchan $nick $support_channel]} error]} {
        putlog "Error verificando presencia de $nick: $error"
    }
    
    if {$is_present} {
        # ¡El usuario volvió! Mantener el ticket
        putserv "PRIVMSG $ops_channel :✅ Usuario $nick reconectó, ticket $t_id reactivado."
        unset pending_reconnects($t_id)
        return
    }
    
    # Usuario no volvió - eliminar ticket
    unset pending_reconnects($t_id)
    with_ticket_lock {
        remove_specific_ticket $t_id $nick
    }
}

proc remove_specific_ticket {t_id nick} {
    global tickets_file ops_channel
    
    set lines [get_cached_tickets]
    set cleaned {}
    set removed 0
    
    foreach line $lines {
        if {$line eq ""} continue
        set parts [split $line ";"]
        if {[llength $parts] < 5} {
            lappend cleaned $line
            continue
        }
        
        set line_id [lindex $parts 0]
        set tnick [lindex $parts 1]
        
        if {[string equal $line_id $t_id] && [string equal -nocase $tnick $nick]} {
            set removed 1
            putserv "PRIVMSG $ops_channel :❌ Ticket $t_id de $nick eliminado (no reconectó a tiempo)."
            continue
        }
        lappend cleaned $line
    }
    
    if {$removed} {
        write_file $tickets_file [join $cleaned "\n"]
        # Actualizar cache
        global tickets_cache cache_timestamp
        set tickets_cache [split [join $cleaned "\n"] "\n"]
        set cache_timestamp [clock seconds]
    }
}

proc remove_unassigned_user_tickets {nick} {
    global tickets_file ops_channel
    
    set lines [get_cached_tickets]
    set cleaned {}
    set removed 0
    
    foreach line $lines {
        if {$line eq ""} continue
        set parts [split $line ";"]
        if {[llength $parts] < 5} {
            lappend cleaned $line
            continue
        }
        
        set tnick [lindex $parts 1]
        set tasign [lindex $parts 4]
        
        if {[string equal -nocase $tnick $nick] && ($tasign eq "-" || $tasign eq "")} {
            # Solo eliminar tickets NO asignados
            set removed 1
            continue
        }
        lappend cleaned $line
    }
    
    if {$removed} {
        write_file $tickets_file [join $cleaned "\n"]
        # Actualizar cache
        global tickets_cache cache_timestamp
        set tickets_cache [split [join $cleaned "\n"] "\n"]
        set cache_timestamp [clock seconds]
        putserv "PRIVMSG $ops_channel :ℹ️ Tickets no asignados de $nick eliminados por desconexión."
    }
}

bind part - * user_left
bind sign - * user_left

### =======================
### COMANDOS BOT MEJORADOS
### =======================

# Crear ticket (!ticket <detalle>)
bind pub - "!ticket" create_ticket
proc create_ticket {nick uhost hand chan text} {
    global tickets_file ops_channel support_channel max_daily_tickets akick_time

    # Verificar licencia antes de ejecutar
    if {![license::is_validated]} {
        putserv "NOTICE $nick :❌ Sistema no autorizado. Contacta al administrador."
        return
    }
    
    if {$chan ne $support_channel} { 
        putserv "NOTICE $nick :⚠️ Solo puedes crear tickets en $support_channel."
        return 
    }
    
    if {$text eq ""} { 
        putserv "NOTICE $nick :Uso: !ticket <detalle de tu problema>"
        return 
    }

    # Verificar flood
    if {[check_flood $nick]} {
        putserv "NOTICE $nick :🚫 Estás enviando comandos demasiado rápido."
        return
    }

    with_ticket_lock {
        set data [read_file_safe $tickets_file]
        set count 0
        foreach line [split $data "\n"] {
            if {$line eq ""} continue
            set parts [split $line ";"]
            if {[llength $parts] < 5} continue
            set tnick [lindex $parts 1]
            set tasign [lindex $parts 4]
            # Solo contar tickets activos (no cerrados) del mismo usuario
            if {[string equal -nocase $tnick $nick] && $tasign ne "CLOSED"} {
                incr count
            }
        }

        if {$count >= $max_daily_tickets} {
            putserv "NOTICE $nick :❌ Has excedido el límite diario de tickets. Debes esperar 24 horas para crear un nuevo ticket."
            putserv "KICK $support_channel $nick :🚫 Has superado el límite de solicitudes de ayuda. Vuelve en 24h."
            putserv "CS akick $support_channel add $uhost Has sido sancionado por exceder el límite de solicitudes en $support_channel."
            utimer $akick_time [list putserv "CS akick $support_channel del $uhost"]
            return
        }

        set restante [expr {$max_daily_tickets - $count}]
        if {$restante > 0} {
            putserv "NOTICE $nick :ℹ️ Puedes crear $restante ticket(s) más hoy."
        }

        set timestamp [clock seconds]
        set ticket_id $timestamp
        set line "$ticket_id;$nick;[maskhost $uhost];$text;-"
        set fp [open $tickets_file a]
        puts $fp $line
        close $fp

        # Actualizar cache
        global tickets_cache cache_timestamp
        set tickets_cache [split [read_file_safe $tickets_file] "\n"]
        set cache_timestamp [clock seconds]
    }

    putserv "NOTICE $nick :✅ Ticket creado (ID $ticket_id). Un operador te atenderá pronto."
    putserv "MODE $support_channel +v $nick"
    putserv "PRIVMSG $ops_channel :✅ Nuevo ticket $ticket_id de $nick → $text"
    putlog "✅ Ticket $ticket_id creado por $nick: $text"
}

# Ver tickets (!tickets)
bind pub - "!tickets" show_tickets
proc show_tickets {nick uhost hand chan text} {
    global tickets_file ops_channel

    # Verificar licencia antes de ejecutar
    if {![license::is_validated]} {
        putserv "NOTICE $nick :❌ Sistema no autorizado. Contacta al administrador."
        return
    }

    if {$chan ne $ops_channel} { return }

    set lines [get_cached_tickets]
    if {[llength $lines] == 0 || ($lines eq "")} {
        putserv "PRIVMSG $ops_channel :❌ No hay tickets abiertos."
        return
    }

    set items [list]
    foreach line $lines {
        set line_trimmed [string trim $line]
        if {$line_trimmed ne "" && [llength [split $line_trimmed ";"]] >= 5} {
            lappend items $line_trimmed
        }
    }

    if {[llength $items] == 0} {
        putserv "PRIVMSG $ops_channel :❌ No hay tickets abiertos."
        return
    }

    putserv "PRIVMSG $ops_channel :✅ Lista de tickets abiertos ([llength $items]):"
    set count 0
    foreach line $items {
        incr count
        set parts [split $line ";"]
        set tid [lindex $parts 0]
        set tnick [lindex $parts 1]
        set thost [lindex $parts 2]
        set detalle [lindex $parts 3]
        set asign [lindex $parts 4]
        
        if {$asign eq "-" || $asign eq ""} {
            set asign "sin asignar"
        }
        
        putserv "PRIVMSG $ops_channel :$count) #$tid - $tnick → $detalle (Asignado: $asign)"
    }
}

# Tomar ticket (!ayuda)
bind pub - "!ayuda" take_ticket
proc take_ticket {opnick uhost hand chan text} {
    global tickets_file ops_channel

    # Verificar licencia antes de ejecutar
    if {![license::is_validated]} {
        putserv "NOTICE $opnick :❌ Sistema no autorizado. Contacta al administrador."
        return
    }

    if {$chan ne $ops_channel} { return }
    if {$text eq ""} {
        putserv "PRIVMSG $ops_channel :⚠️ Uso: !ayuda <nick|id>"
        return
    }

    with_ticket_lock {
        set lines [get_cached_tickets]
        set cleaned {}
        set found 0

        foreach line $lines {
            if {$line eq ""} continue
            set parts [split $line ";"]
            if {[llength $parts] < 5} { 
                lappend cleaned $line
                continue 
            }

            set t_id [lindex $parts 0]
            set tnick [lindex $parts 1]
            set thost [lindex $parts 2]
            set detalle [lindex $parts 3]
            set tasign [lindex $parts 4]

            if {$text == $t_id || [string equal -nocase $text $tnick]} {
                set found 1
                if {$tasign ne "-" && $tasign ne ""} {
                    putserv "PRIVMSG $ops_channel :⚠️ Ticket $t_id ya tomado por $tasign."
                    lappend cleaned $line
                } else {
                    set line "$t_id;$tnick;$thost;$detalle;$opnick"
                    putserv "PRIVMSG $ops_channel :✅ $opnick atenderá ticket $t_id de $tnick → $detalle"
                    putserv "NOTICE $tnick :✅ Hola $tnick, el operador $opnick atenderá tu solicitud con número de ticket #$t_id."
                    lappend cleaned $line
                }
            } else {
                lappend cleaned $line
            }
        }

        if {[llength $cleaned] > 0} {
            write_file $tickets_file [join $cleaned "\n"]
            # Actualizar cache
            global tickets_cache cache_timestamp
            set tickets_cache $cleaned
            set cache_timestamp [clock seconds]
        }
        
        if {!$found} { 
            putserv "PRIVMSG $ops_channel :❌ No se encontró ticket para $text" 
        }
    }
}

# Finalizar ticket (!fin)
bind pub - "!fin" close_ticket
proc close_ticket {nick uhost hand chan text} {
    global tickets_file ops_channel support_channel ticket_ban_time

    # Verificar licencia antes de ejecutar
    if {![license::is_validated]} {
        putserv "NOTICE $nick :❌ Sistema no autorizado. Contacta al administrador."
        return
    }

    if {$chan ne $ops_channel} { return }
    if {$text eq ""} {
        putserv "PRIVMSG $ops_channel :Uso: !fin <nick|id>"
        return
    }

    with_ticket_lock {
        set lines [get_cached_tickets]
        set cleaned {}
        set found 0
        set user_to_kick ""
        set user_host ""

        foreach line $lines {
            if {$line eq ""} continue
            set parts [split $line ";"]
            if {[llength $parts] < 5} { 
                lappend cleaned $line
                continue 
            }

            set t_id [lindex $parts 0]
            set tnick [lindex $parts 1]
            set thost [lindex $parts 2]
            set detalle [lindex $parts 3]
            set tasign [lindex $parts 4]

            if {$text == $t_id || [string equal -nocase $text $tnick]} {
                set found 1
                set user_to_kick $tnick
                set user_host $thost
                
                if {$text == $t_id} {
                    putserv "PRIVMSG $ops_channel :✔ Ticket $t_id de $tnick cerrado."
                    putserv "NOTICE $tnick :✅ Tu ticket #$t_id ha sido cerrado por $nick."
                } else {
                    putserv "PRIVMSG $ops_channel :✔ Todos los tickets de $tnick cerrados por $nick."
                    putserv "NOTICE $tnick :✅ Todos tus tickets han sido cerrados por $nick."
                }
                continue
            }
            lappend cleaned $line
        }

        if {[llength $cleaned] > 0} {
            write_file $tickets_file [join $cleaned "\n"]
            # Actualizar cache
            global tickets_cache cache_timestamp
            set tickets_cache $cleaned
            set cache_timestamp [clock seconds]
        }

        if {$found && $user_to_kick ne ""} {
            putserv "MODE $support_channel -v $user_to_kick"
            
            # Solo aplicar ban si se cierra por nick (todos los tickets)
            if {![string is integer -strict $text]} {
                set host_mask "*!*@[lindex [split $user_host @] 1]"
                putserv "MODE $support_channel +b $host_mask"
                putserv "KICK $support_channel $user_to_kick :✅ Soporte terminado. Todos tus tickets han sido cerrados, gracias por visitarnos."
                utimer $ticket_ban_time [list putserv "MODE $support_channel -b $host_mask"]
            }
        }

        if {!$found} { 
            putserv "PRIVMSG $ops_channel :❌ No se encontró ticket para $text" 
        }
    }
}

# Revisión automática de tickets
proc check_tickets {} {
    global tickets_file ticket_timers ops_channel
    # Verificar licencia antes de ejecutar
    if {![license::is_validated]} {
        return
    }
    
    set now [clock seconds]
    
    with_ticket_lock {
        set lines [get_cached_tickets]
        set cleaned {}

        foreach line $lines {
            if {$line eq ""} continue
            set parts [split $line ";"]
            if {[llength $parts] < 5} { continue }
            
            set t_id [lindex $parts 0]
            set tnick [lindex $parts 1]
            set timestamp [lindex $parts 0]
            set tasign [lindex $parts 4]

            if {[string is integer -strict $timestamp]} {
                set age [expr {$now - $timestamp}]
            } else { 
                set age 0 
            }

            if {$age >= $ticket_timers(autoclose) && ($tasign eq "-" || $tasign eq "")} {
                putserv "NOTICE $tnick :❌ Tu ticket ha sido cerrado automáticamente por inactividad."
                putserv "PRIVMSG $ops_channel :❌ Ticket $t_id de $tnick cerrado automáticamente por inactividad."
                putlog "Ticket $t_id de $tnick cerrado automáticamente por inactividad."
                continue
            }

            if {$age >= $ticket_timers(escalate) && ($tasign eq "-" || $tasign eq "")} {
                putserv "PRIVMSG $ops_channel :🚨 Atención: ticket #$t_id de $tnick lleva 30 minutos pendiente."
            }

            if {$age >= $ticket_timers(warn) && ($tasign eq "-" || $tasign eq "")} {
                putserv "NOTICE $tnick :⏳ Tu solicitud sigue pendiente. Paciencia por favor."
            }

            lappend cleaned $line
        }

        if {[llength $cleaned] > 0} {
            write_file $tickets_file [join $cleaned "\n"]
            # Actualizar cache
            global tickets_cache cache_timestamp
            set tickets_cache $cleaned
            set cache_timestamp [clock seconds]
        }
    }
}

# Iniciar el timer de revisión (SOLO UNA VEZ)
timer 300 check_tickets

# Comando de ayuda (!help)
bind pub - "!help" show_help

proc show_help {nick uhost hand chan text} {
    global support_channel ops_channel bot_name
    
    # Verificar licencia antes de ejecutar
    if {![license::is_validated]} {
        putserv "NOTICE $nick :❌ Sistema no autorizado. Contacta al administrador."
        return
    }
    
    if {$chan eq $support_channel} {
        putserv "NOTICE $nick :         ℹ **CENTRO DE AYUDA** ℹ      "
        putserv "NOTICE $nick :"
        putserv "NOTICE $nick : **Comandos disponibles para usuarios:**    "
        putserv "NOTICE $nick :   ℹ️ **!ticket <mensaje>** 			   "
        putserv "NOTICE $nick :      ◦ Crear un nuevo ticket de soporte    "
        putserv "NOTICE $nick :      ◦ Ejemplo: !ticket No puedo conectarme"
        putserv "NOTICE $nick :   ℹ️ **!help**				   "
        putserv "NOTICE $nick :      ◦ Mostrar este menú de ayuda          "
        putserv "NOTICE $nick :   ℹ️  **Información importante:** 	   "
        putserv "NOTICE $nick :      ◦ Un operador te atenderá en breve    "
        putserv "NOTICE $nick :      ◦ Por favor sé específico en tu problema   "
        putserv "NOTICE $nick :      ◦ Límite: 5 tickets por día por usuario    "
        putserv "NOTICE $nick :"
        putserv "NOTICE $nick :	ℹ️ **Tip:** Describe tu problema con detalle para una atención más rápida.	"
        
    } elseif {$chan eq $ops_channel} {
        putserv "PRIVMSG $ops_channel :       ℹ️ **PANEL DE OPERADORES** ℹ️    		  "
        putserv "PRIVMSG $ops_channel :"
        putserv "PRIVMSG $ops_channel :  	**Comandos de administración de tickets:**        "
        putserv "PRIVMSG $ops_channel :   ✅ **!tickets** 				  "
        putserv "PRIVMSG $ops_channel :      ◦ Listar todos los tickets pendientes            "
        putserv "PRIVMSG $ops_channel :      ◦ Muestra ID, usuario y estado                   "
        putserv "PRIVMSG $ops_channel :   ✅ **!ayuda <ID|nick>** 			  "
        putserv "PRIVMSG $ops_channel :      ◦ Tomar un ticket para atención                  "
        putserv "PRIVMSG $ops_channel :      ◦ Ejemplo: !ayuda 12345  o  !ayuda UsuarioEjemplo"
        putserv "PRIVMSG $ops_channel :   ✅ **!fin <ID|nick>** 			  "
        putserv "PRIVMSG $ops_channel :      ◦ Cerrar ticket específico o todos de un usuario "
        putserv "PRIVMSG $ops_channel :      ◦ !fin 12345 → cierra ticket ID 12345            "
        putserv "PRIVMSG $ops_channel :      ◦ !fin Usuario → cierra TODOS sus tickets        "
        putserv "PRIVMSG $ops_channel :   ℹ️ **!estadisticas** 			  "
        putserv "PRIVMSG $ops_channel :      ◦ Ver estadísticas del sistema                   "
        putserv "PRIVMSG $ops_channel :   ℹ️  **!info** 				  "
        putserv "PRIVMSG $ops_channel :      ◦ Ver información de configuración del sistema   "
        putserv "PRIVMSG $ops_channel :"
        putserv "PRIVMSG $ops_channel :  **Tiempos automáticos del sistema:**                 "
        putserv "PRIVMSG $ops_channel :   ⏰ 10 min → Aviso de espera al usuario  "
        putserv "PRIVMSG $ops_channel :   ⏰ 30 min → Escalación a operadores    "
        putserv "PRIVMSG $ops_channel :   ⏰ 60 min → Cierre automático            "
        putserv "PRIVMSG $ops_channel :   ⏰ 10 min → Eliminación si usuario no regresa    "
        putserv "PRIVMSG $ops_channel :"
        putserv "PRIVMSG $ops_channel : ℹ️**Recordatorio:** Siempre notificar al usuario cuando se tome o cierre un ticket."
        
    } else {
        putserv "NOTICE $nick :             ℹ️ **AVISO** ℹ️             "
        putserv "NOTICE $nick :"
        putserv "NOTICE $nick :  Este comando solo está disponible en:   "
        putserv "NOTICE $nick :                                          "
        putserv "NOTICE $nick :   ℹ️ **$support_channel** 	     "
        putserv "NOTICE $nick :      ◦ Para solicitar ayuda técnica      "
        putserv "NOTICE $nick :                                          "
        putserv "NOTICE $nick :   ℹ️  **$ops_channel**			 "
        putserv "NOTICE $nick :      ◦ Para operadores del sistema       "
    }
}

# Comando de estadísticas para operadores
bind pub - "!estadisticas" show_stats
bind pub - "!stats" show_stats
bind pub - "!info" show_system_info
# -------------------------------------------------------------
# 📊 Estadísticas del sistema de tickets (versión final)
# -------------------------------------------------------------
proc show_stats {nick uhost hand chan text} {
    global tickets_file ops_channel support_channel

    # Verificar licencia antes de ejecutar
    if {![license::is_validated]} {
        putserv "NOTICE $nick :❌ Sistema no autorizado. Contacta al administrador."
        return
    }

    # Solo operadores pueden usarlo
    if {$chan ne $ops_channel} { return }

    # Cargar tickets desde memoria (más rápido y evita I/O repetida)
    set lines [get_cached_tickets]

    set total_tickets 0
    set pending_tickets 0
    set inprogress_tickets 0
    set closed_tickets 0
    array set operators {}

    # Procesar cada línea del archivo de tickets
    foreach line $lines {
        set line_trimmed [string trim $line]
        if {$line_trimmed eq ""} continue
        
        set parts [split $line_trimmed ";"]
        if {[llength $parts] < 5} continue

        incr total_tickets
        set asignado [string trim [lindex $parts 4]]

        # Clasificación de ticket
        if {[string equal -nocase $asignado "CLOSED"]} {
            incr closed_tickets
        } elseif {$asignado eq "-" || $asignado eq ""} {
            incr pending_tickets
        } else {
            incr inprogress_tickets

            # Contar tickets por operador
            if {[info exists operators($asignado)]} {
                incr operators($asignado)
            } else {
                set operators($asignado) 1
            }
        }
    }

    # Cálculos derivados
    set processed [expr {$inprogress_tickets + $closed_tickets}]

    # Enviar reporte al canal de operadores
    putserv "PRIVMSG $ops_channel :────────────────────────────────────"
    putserv "PRIVMSG $ops_channel :    📊 **RESUMEN DEL SISTEMA DE TICKETS**"
    putserv "PRIVMSG $ops_channel :────────────────────────────────────"
    putserv "PRIVMSG $ops_channel :📝 Total de tickets: $total_tickets"
    putserv "PRIVMSG $ops_channel :⭕ Pendientes (sin asignar): $pending_tickets"
    putserv "PRIVMSG $ops_channel :🔄 En proceso (asignados): $inprogress_tickets"
    putserv "PRIVMSG $ops_channel :✅ Resueltos (CLOSED): $closed_tickets"
    putserv "PRIVMSG $ops_channel :📦 Procesados (en proceso + resueltos): $processed"

    # Porcentaje de eficiencia
    if {$total_tickets > 0} {
        set porcentaje [expr {double($processed) * 100.0 / $total_tickets}]
        putserv "PRIVMSG $ops_channel :📈 Eficiencia: [format "%.2f" $porcentaje]%"
    }

    # Tickets por operador
    if {[array size operators] > 0} {
        putserv "PRIVMSG $ops_channel :────────────────────────────────────"
        putserv "PRIVMSG $ops_channel :👤 **Tickets gestionados por operador:**"

        set count 0
        foreach op [lsort -dictionary [array names operators]] {
            incr count
            if {$count <= 10} {
                putserv "PRIVMSG $ops_channel :   • $op → $operators($op) tickets"
            }
        }

        if {[array size operators] > 10} {
            set restantes [expr {[array size operators] - 10}]
            putserv "PRIVMSG $ops_channel :   ... y $restantes operadores más"
        }
    }

    putserv "PRIVMSG $ops_channel :────────────────────────────────────"
    putserv "PRIVMSG $ops_channel :"
}

# --- AÑADIMOS show_system_info requerido por el validador de licencia ---
proc show_system_info {nick uhost hand chan text} {
    global bot_name bot_version ops_channel support_channel ticket_timers max_daily_tickets

    # Verificar licencia antes de ejecutar
    if {![license::is_validated]} {
        putserv "NOTICE $nick :❌ Sistema no autorizado. Contacta al administrador."
        return
    }

    # Solo operadores pueden usarlo
    if {$chan ne $ops_channel} { return }

    set hora [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]

    putserv "PRIVMSG $ops_channel :────────────────────────────────────"
    putserv "PRIVMSG $ops_channel :🔧 **INFORMACIÓN DEL SISTEMA**"
    putserv "PRIVMSG $ops_channel :────────────────────────────────────"
    putserv "PRIVMSG $ops_channel :🤖 Bot: $bot_name v$bot_version"
    putserv "PRIVMSG $ops_channel :🕒 Hora actual: $hora"
    putserv "PRIVMSG $ops_channel :📌 Canal soporte: $support_channel"
    putserv "PRIVMSG $ops_channel :📌 Canal operadores: $ops_channel"
    putserv "PRIVMSG $ops_channel :📌 Límite diario: $max_daily_tickets tickets/usuario"
    putserv "PRIVMSG $ops_channel :📌 Temporizadores (min): Aviso=[expr {$ticket_timers(warn)/60}] Escalación=[expr {$ticket_timers(escalate)/60}] Cierre=[expr {$ticket_timers(autoclose)/60}]"
    putserv "PRIVMSG $ops_channel :────────────────────────────────────"
}

# Mensaje de carga en partyline
puts "=============================================="
puts "Sistema de Tickets v$bot_version Cargado Exitosamente"
puts "Script: [file tail [info script]]"
puts "Hora: [clock format [clock seconds]]"
puts "=============================================="
show_bot_info
