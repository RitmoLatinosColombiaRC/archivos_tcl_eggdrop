#------------------------------------------------------------#
#        🎟️ Sistema de Tickets – Ritmo Latinos Colombia      #
#------------------------------------------------------------#
# Autor: Atómico (Founder)
# Versión: 1.0
# Email: r.ritmo.latinos@gmail.com
#
# 📌 Descripción:
# Servicio de ayuda y gestión de tickets para usuarios y operadores
# REQUIERE validación de licencia previa
#------------------------------------------------------------#

# Verificar que la licencia fue validada antes de continuar
if {![info exists license::validation_passed] || !$license::validation_passed} {
    puts "❌ ERROR: La licencia no ha sido validada. Cargue primero license_validation.tcl"
    return
}

### =======================
### CONFIGURACIÓN
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

### =======================
### UTILIDADES
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
    return [read_file $filename]
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
### CONTROL ANTIFLOOD
### =======================
array set flood_limit {}
array set flood_count {}

proc check_flood {nick} {
    global flood_limit flood_count
    set now [clock seconds]

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
set bot_version "1.0"
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

        putserv "PRIVMSG $ops_channel : ℹ$bot_name v$bot_version iniciado correctamente."
        
    } err]} {
        puts "⚠️ Error cargando el script de tickets: $err"
    }
}

### =======================
### AUTO-VOICE PARA USUARIOS
### =======================
set support_channel "#ritmolatinos_help"

proc user_joined {nick uhost hand chan} {
    global support_channel
    if {$chan eq $support_channel} {
        if {![is_voiced $nick $chan]} {
            putserv "MODE $support_channel +v $nick"
            putserv "NOTICE $nick :✅ Bienvenido a $support_channel! Ahora tienes voz para comunicarte. Usa !ticket <mensaje> para que un operador te atienda."
        }
    }
}

bind join - * user_joined

### =======================
### COMANDOS BOT
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

    set data [read_file_safe $tickets_file]
    set count 0
    foreach line [split $data "\n"] {
        if {$line eq ""} continue
        set parts [split $line ";"]
        set tnick [lindex $parts 1]
        if {$tnick eq $nick} { incr count }
    }

    if {$count >= $max_daily_tickets} {
        putserv "NOTICE $nick :❌ Has excedido el límite diario de tickets. Debes esperar 24 horas para crear un nuevo ticket."
        putserv "KICK $support_channel $nick :🚫 Has superado el límite de solicitudes de ayuda. Vuelve en 24h."
        putserv "/cs akick $support_channel add $uhost Has sido sancionado por exceder el límite de solicitudes en $support_channel."
        utimer $akick_time [list putserv ".MSG ChanServ akick $support_channel del $uhost"]
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

    set data [read_file_safe $tickets_file]
    if {$data eq ""} {
        putserv "PRIVMSG $ops_channel :❌ No hay tickets abiertos."
        return
    }

    set items [list]
    foreach line [split $data "\n"] {
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

    set lines [split [read_file_safe $tickets_file] "\n"]
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

        if {$text eq $t_id || $text eq $tnick} {
            set found 1
            if {$tasign ne "" && $tasign ne "-"} {
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

    write_file $tickets_file [join $cleaned "\n"]
    if {!$found} { 
        putserv "PRIVMSG $ops_channel :❌ No se encontró ticket para $text" 
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

    set lines [split [read_file_safe $tickets_file] "\n"]
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

        if {$text eq $t_id} {
            set found 1
            set user_to_kick $tnick
            set user_host $thost
            putserv "PRIVMSG $ops_channel :✔ Ticket $t_id de $tnick cerrado."
            putserv "NOTICE $tnick :✅ Tu ticket #$t_id ha sido cerrado por $nick."
            continue
        } elseif {$text eq $tnick} {
            set found 1
            set user_to_kick $tnick
            set user_host $thost
            putserv "PRIVMSG $ops_channel :✔ Todos los tickets de $tnick cerrados por $nick."
            putserv "NOTICE $tnick :✅ Todos tus tickets han sido cerrados por $nick."
            continue
        }
        lappend cleaned $line
    }

    write_file $tickets_file [join $cleaned "\n"]

    if {$found && $user_to_kick ne ""} {
        putserv "MODE $support_channel -v $user_to_kick"
        
        if {[string is integer -strict $text]} {
            putlog "Ticket $text cerrado por $nick"
        } else {
            set host_mask "*!*@[lindex [split $user_host @] 1]"
            putserv "MODE $support_channel +b $host_mask"
            putserv "KICK $support_channel $user_to_kick :✅ Soporte terminado. Todos tus tickets han sido cerrados, gracias por visitarnos."
            utimer $ticket_ban_time [list putserv ".MODE $support_channel -b $host_mask"]
        }
    }

    if {!$found} { 
        putserv "PRIVMSG $ops_channel :❌ No se encontró ticket para $text" 
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
    set lines [split [read_file_safe $tickets_file] "\n"]
    set cleaned {}

    foreach line $lines {
        if {$line eq ""} continue
        set parts [split $line ";"]
        if {[llength $parts] < 5} { continue }
        
        set t_id [lindex $parts 0]
        set nick [lindex $parts 1]
        set timestamp [lindex $parts 0]
        set tasign [lindex $parts 4]

        if {[string is integer -strict $timestamp]} {
            set age [expr {$now - $timestamp}]
        } else { 
            set age 0 
        }

        if {$age >= $ticket_timers(autoclose)} {
            putserv "NOTICE $nick :❌Tu ticket ha sido cerrado automáticamente."
            putserv "PRIVMSG $ops_channel :❌Ticket de $nick cerrado automáticamente."
            putlog "Ticket $t_id de $nick cerrado automáticamente."
            continue
        }

        if {$age >= $ticket_timers(escalate) && ($tasign eq "-" || $tasign eq "")} {
            putserv "PRIVMSG $ops_channel :Atención: ⏳ ticket de $nick lleva 30 minutos pendiente."
        }

        if {$age >= $ticket_timers(warn) && ($tasign eq "-" || $tasign eq "")} {
            putserv "NOTICE $nick :⏳ Tu solicitud sigue pendiente. Paciencia por favor."
            putserv "PRIVMSG $ops_channel :⏳ Ticket #$t_id de $nick lleva 10 minutos sin respuesta."
        }

        lappend cleaned $line
    }

    write_file $tickets_file [join $cleaned "\n"]
    utimer 300 check_tickets
}

utimer 300 check_tickets


# Autoeliminar tickets si usuario no vuelve
bind part - * user:left
bind sign - * user:left
proc user:left {nick uhost hand chan text} {
    global tickets_file support_channel max_ticket_wait ops_channel
    
    # Verificar licencia antes de ejecutar
    if {![license::is_validated]} {
        return
    }
    
    if {$chan ne $support_channel} { return }
    
    set lines [split [read_file_safe $tickets_file] "\n"]
    foreach line $lines {
        if {$line eq ""} continue
        set parts [split $line ";"]
        if {[llength $parts] < 5} continue
        set t_id [lindex $parts 0]
        set tnick [lindex $parts 1]
        if {$tnick eq $nick} {
            putserv "PRIVMSG $ops_channel :ℹ️ Ticket $t_id de $nick se mantiene $max_ticket_wait segundos para posible reconexión."
            utimer $max_ticket_wait [list remove_ticket_if_not_back $t_id $nick]
        }
    }
}

proc remove_ticket_if_not_back {t_id nick} {
    global tickets_file ops_channel
    
    # Verificar licencia antes de ejecutar
    if {![license::is_validated]} {
        return
    }
    
    set lines [split [read_file_safe $tickets_file] "\n"]
    set cleaned {}
    set removed 0
    foreach line $lines {
        if {$line eq ""} continue
        set parts [split $line ";"]
        if {[llength $parts] < 5} continue
        set line_id [lindex $parts 0]
        set tnick [lindex $parts 1]
        if {$line_id eq $t_id && $tnick eq $nick} {
            incr removed
            continue
        }
        lappend cleaned $line
    }
    if {$removed} {
        write_file $tickets_file [join $cleaned "\n"]
        putserv "PRIVMSG $ops_channel :ℹ️Ticket $t_id de $nick eliminado automáticamente (usuario no volvió)."
        putlog "ℹ️Ticket $t_id de $nick eliminado automáticamente."
    }
}

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
        putserv "NOTICE $nick :   ℹ **!ticket <mensaje>** 				   "
        putserv "NOTICE $nick :      ◦ Crear un nuevo ticket de soporte    "
        putserv "NOTICE $nick :      ◦ Ejemplo: !ticket No puedo conectarme"
        putserv "NOTICE $nick :   ℹ **!help**							   "
        putserv "NOTICE $nick :      ◦ Mostrar este menú de ayuda          "
        putserv "NOTICE $nick :   ℹ  **Información importante:** 		   "
        putserv "NOTICE $nick :      ◦ Un operador te atenderá en breve    "
        putserv "NOTICE $nick :      ◦ Por favor sé específico en tu problema   "
        putserv "NOTICE $nick :      ◦ Límite: 5 tickets por día por usuario    "
        putserv "NOTICE $nick :"
        putserv "NOTICE $nick :		ℹ **Tip:** Describe tu problema con detalle para una atención más rápida.	"
        
    } elseif {$chan eq $ops_channel} {
        putserv "PRIVMSG $ops_channel :       ℹ **PANEL DE OPERADORES** ℹ   			  "
        putserv "PRIVMSG $ops_channel :"
        putserv "PRIVMSG $ops_channel : 	**Comandos de administración de tickets:**        "
        putserv "PRIVMSG $ops_channel :   ✅ **!tickets** 									  "
        putserv "PRIVMSG $ops_channel :      ◦ Listar todos los tickets pendientes            "
        putserv "PRIVMSG $ops_channel :      ◦ Muestra ID, usuario y estado                   "
        putserv "PRIVMSG $ops_channel :   ✅ **!ayuda <ID|nick>** 							  "
        putserv "PRIVMSG $ops_channel :      ◦ Tomar un ticket para atención                  "
        putserv "PRIVMSG $ops_channel :      ◦ Ejemplo: !ayuda 12345  o  !ayuda UsuarioEjemplo"
        putserv "PRIVMSG $ops_channel :   ✅ **!fin <ID|nick>** 							  "
        putserv "PRIVMSG $ops_channel :      ◦ Cerrar ticket específico o todos de un usuario "
        putserv "PRIVMSG $ops_channel :      ◦ !fin 12345 → cierra ticket ID 12345            "
        putserv "PRIVMSG $ops_channel :      ◦ !fin Usuario → cierra TODOS sus tickets        "
        putserv "PRIVMSG $ops_channel :   ℹ **!estadisticas** 								  "
        putserv "PRIVMSG $ops_channel :      ◦ Ver estadísticas del sistema                   "
        putserv "PRIVMSG $ops_channel :   ℹ  **!info** 									  "
        putserv "PRIVMSG $ops_channel :      ◦ Ver información de configuración del sistema   "
        putserv "PRIVMSG $ops_channel :"
        putserv "PRIVMSG $ops_channel :  **Tiempos automáticos del sistema:**                 "
        putserv "PRIVMSG $ops_channel :   ⏰ 10 min → Aviso de espera al usuario 			  "
        putserv "PRIVMSG $ops_channel :   ⏰ 30 min → Escalación a operadores 				  "
        putserv "PRIVMSG $ops_channel :   ⏰ 60 min → Cierre automático 					  "
        putserv "PRIVMSG $ops_channel :   ⏰ 10 min → Eliminación si usuario no regresa 	  "
        putserv "PRIVMSG $ops_channel :"
        putserv "PRIVMSG $ops_channel :ℹ **Recordatorio:** Siempre notificar al usuario cuando se tome o cierre un ticket."
        
    } else {
        putserv "NOTICE $nick :             ℹ **AVISO** ℹ             "
        putserv "NOTICE $nick :"
        putserv "NOTICE $nick :  Este comando solo está disponible en:   "
        putserv "NOTICE $nick :                                          "
        putserv "NOTICE $nick :   ℹ **$support_channel** 			     "
        putserv "NOTICE $nick :      ◦ Para solicitar ayuda técnica      "
        putserv "NOTICE $nick :                                          "
        putserv "NOTICE $nick :   ℹ  **$ops_channel**	       			 "
        putserv "NOTICE $nick :      ◦ Para operadores del sistema       "
    }
}

# Comando de estadísticas para operadores
bind pub - "!estadisticas" show_stats
bind pub - "!stats" show_stats

proc show_stats {nick uhost hand chan text} {
    global tickets_file ops_channel support_channel
    
    # Verificar licencia antes de ejecutar
    if {![license::is_validated]} {
        putserv "NOTICE $nick :❌ Sistema no autorizado. Contacta al administrador."
        return
    }

    if {$chan ne $ops_channel} { return }
    
    set data [read_file_safe $tickets_file]
    set total_tickets 0
    set pending_tickets 0
    set assigned_tickets 0
    array set operators {}
    
    foreach line [split $data "\n"] {
        if {$line eq ""} continue
        set parts [split $line ";"]
        if {[llength $parts] < 5} continue
        
        incr total_tickets
        set asignado [lindex $parts 4]
        
        if {$asignado eq "-" || $asignado eq ""} {
            incr pending_tickets
        } else {
            incr assigned_tickets
            if {[info exists operators($asignado)]} {
                incr operators($asignado)
            } else {
                set operators($asignado) 1
            }
        }
    }
    
    putserv "PRIVMSG $ops_channel :      ℹ **ESTADÍSTICAS DEL SISTEMA** ℹ 	 "
    putserv "PRIVMSG $ops_channel :"
    putserv "PRIVMSG $ops_channel :             **Resumen general:**	         "
    putserv "PRIVMSG $ops_channel :   ℹ Total de tickets: $total_tickets        "
    putserv "PRIVMSG $ops_channel :   ❌ Pendientes: $pending_tickets            "
    putserv "PRIVMSG $ops_channel :   ✅ Atendidos: $assigned_tickets            "
    
    if {$total_tickets > 0} {
        set porcentaje [expr {double($assigned_tickets) * 100 / $total_tickets}]
        putserv "PRIVMSG $ops_channel :   ℹ Eficiencia: [format "%.1f" $porcentaje]% "
    }
    
    if {[array size operators] > 0} {
        putserv "PRIVMSG $ops_channel : **Tickets por operador:**                      "
        set count 0
        foreach op [lsort [array names operators]] {
            incr count
            if {$count <= 5} {
                putserv "PRIVMSG $ops_channel :   ℹ $op: $operators($op) tickets      "
            }
        }
        if {[array size operators] > 5} {
            putserv "PRIVMSG $ops_channel :   ... y [expr {[array size operators] - 5}] operadores más "
        }
    }
    
    putserv "PRIVMSG $ops_channel :"
}

# Comando de información del sistema
bind pub - "!info" show_system_info
bind pub - "!sistema" show_system_info

proc show_system_info {nick uhost hand chan text} {
    global bot_name bot_version support_channel ops_channel ticket_timers max_daily_tickets
    
    # Verificar licencia antes de ejecutar
    if {![license::is_validated]} {
        putserv "NOTICE $nick :❌ Sistema no autorizado. Contacta al administrador."
        return
    }

    if {$chan eq $ops_channel} {
        putserv "PRIVMSG $ops_channel :         ℹ **INFORMACIÓN DEL SISTEMA** ℹ     "
        putserv "PRIVMSG $ops_channel :"
        putserv "PRIVMSG $ops_channel : 		ℹ	**Configuración actual:**   ℹ       "
        putserv "PRIVMSG $ops_channel :"
        putserv "PRIVMSG $ops_channel :    Bot: $bot_name v$bot_version          	   "
        putserv "PRIVMSG $ops_channel :    Canal soporte: $support_channel    	 	   "
        putserv "PRIVMSG $ops_channel :    Canal operadores: $ops_channel      	       "
        putserv "PRIVMSG $ops_channel :    Límite diario: $max_daily_tickets tickets/usuario	"
        putserv "PRIVMSG $ops_channel :"
        putserv "PRIVMSG $ops_channel : 		ℹ	**Temporizadores automáticos:**  ℹ            "
        putserv "PRIVMSG $ops_channel :"
        putserv "PRIVMSG $ops_channel :    Aviso: [expr {$ticket_timers(warn)/60}] min | Escalación: [expr {$ticket_timers(escalate)/60}] min "
        putserv "PRIVMSG $ops_channel :    Cierre: [expr {$ticket_timers(autoclose)/60}] min "
        putserv "PRIVMSG $ops_channel :"
    } else {
        putserv "NOTICE $nick :ℹEste comando solo está disponible para operadores en $ops_channel"
    }
}

# Mensaje de carga en partyline
puts "=============================================="
puts "Sistema de Tickets v$bot_version Cargado Exitosamente"
puts "Script: [file tail [info script]]"
puts "Hora: [clock format [clock seconds]]"
puts "=============================================="
show_bot_info