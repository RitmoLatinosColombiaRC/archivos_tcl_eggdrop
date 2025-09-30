#------------------------------------------------------------#
#        🎟️ Sistema de Tickets – Ritmo Latinos Colombia      #
#------------------------------------------------------------#
# Autor: Atómico (Founder)
# Versión: 1.0
# Email: r.ritmo.latinos@gmail.com
# Servidor IRC: irc.chatdetodos.com
# Web: www.ritmolatinoscrc.com
#
# 📌 Descripción:
# Servicio de ayuda y gestión de tickets para usuarios y operadores
# en IRC, desarrollado en Tcl para Eggdrop.
# Permite gestionar solicitudes, asignar tickets a operadores,
# controlar límite de solicitudes, manejo antiflood y cierre automático.
#
# ⚙️ Instalación:
# 1. Copiar estos archivos en la carpeta de scripts del Eggdrop.
# 2. Editar el archivo de configuración (eggdrop.conf) y añadir:
#       source scripts/tickets.tcl
#2.1.Archivo de licencia:
#		source scripts/License.txt		
# 3. Reiniciar el Eggdrop.
#
# 🔧 Configuración:
# - Archivos de tickets y logs
# - Canales de soporte (#Opers_help) y operadores (#Opers o #Opers_admin) o cambialos segun tu criterio.
# - Timers de aviso, escalado y autocierre
# - Ban temporal al finalizar ticket
# - Límite de solicitudes por usuario
#
# 👥 Comandos disponibles
#
# Usuarios (en #Opers_Help) o según tu criterio:
#   !ticket <detalle> → Crear un ticket
#   !help             → Ver comandos de usuario
#
# Operadores (en #Opers) o según tu criterio:
#   !tickets          → Lista de tickets abiertos
#   !ayuda <nick|id>  → Tomar un ticket y notificar al usuario
#   !fin <nick|id>    → Finalizar un ticket, aplicar ban temporal
#   !help             → Lista de comandos operadores
#
# 🛠️ Funciones automáticas:
# - Avisos según tiempo de espera
# - Escalamiento de tickets sin asignar
# - Cierre automático tras 1 hora
# - Eliminación si el usuario no vuelve tras 5 minutos de salir
# - Ban temporal al cerrar ticket
# - Control antiflood y límite de solicitudes por usuario
#
#------------------------------------------------------------#
# =========================================================
# 🎟️ Advertencia
# =========================================================
#Este script esta encriptado con 4 capas de seguridad,- 
#si intentas modificar el codigo sea de licencia o el sistema de ticket este dejara de funcionar,-
#esto puede ocasionar que la licencia se reboque o tu bot quede fuera de línea.
#Si necesitas modificar el codigo para implementar algúna otra funcion,-
#comúnicate con nosotros enviandonos la informacion detallada y asi podremos brindarte una solucion precisa.
# =========================================================
# 🎟️ Verificación de Licencia
# =========================================================

package require json
package require Tcl 8.5

set license_file "scripts/license.txt"

# Lee el contenido de un archivo
proc read_file {filename} {
    if {![file exists $filename]} { return "" }
    set fp [open $filename r]
    set data [read $fp]
    close $fp
    return $data
}

# Extrae el valor de cada campo del archivo de licencia
proc get_license_value {data key} {
    if {[regexp "$key=(\[^\r\n\]+)" $data -> value]} {
        set value [string trim $value]
        return $value
    }
    return ""
}

# Codifica parámetros para URL (para caracteres especiales)
proc url_encode {str} {
    set out ""
    foreach c [split $str ""] {
        if {[regexp {[A-Za-z0-9._~-]} $c]} {
            append out $c
        } else {
            append out [format "%%%02X" [scan $c %c]]
        }
    }
    return $out
}

# Procedimiento principal de validación de licencia
proc validate_license {} {
    global license_file

    puts "🔍 Iniciando verificación de licencia..."
    
    # Leer archivo de licencia
    set data [read_file $license_file]
    if {$data eq ""} {
        puts "❌ No se encontró license.txt. El bot no puede iniciarse."
        exit
    }

    # Extraer valores del archivo de licencia
    set email [get_license_value $data "email"]
    set key   [get_license_value $data "key"]
    set botid [get_license_value $data "botid"]

    # Verificar que todos los campos estén presentes
    if {$email eq "" || $key eq "" || $botid eq ""} {
        puts "❌ license.txt incompleto. Revisar email, key y botid."
        exit
    }

    puts "📧 Email: $email"
    puts "🔑 Key: [string range $key 0 15]..."
    puts "ℹ️ BotID: $botid"
    puts ""

    # Verificar formato de la key
    if {[string length $key] != 64} {
        puts "❌ Error: La license key debe tener 64 caracteres"
        exit
    }

    # Codificar parámetros para URL
    set email_enc [url_encode $email]
    set key_enc   [url_encode $key]
    set botid_enc [url_encode $botid]

    # Construir URL de validación
    set url "https://script.google.com/macros/s/AKfycbwY0eL8VGeV0XQCs-oEjiffG9QBGWEIH5Nipe3KjeGfOCPo31I36N1ZAvi5XuPeuAaP/exec?action=validate&email=$email_enc&license=$key_enc&botid=$botid_enc"

    # Llamada HTTPS usando curl SIGUIENDO redirecciones automáticamente (-L)
    puts "🌐 Conectando con el servidor de licencias..."
    if {[catch {set response [exec curl -s -L --max-time 15 $url]} err]} {
        puts "❌ Error de conexión al servidor de licencias: $err"
        exit
    }

    # Verificar si la respuesta está vacía
    if {$response eq ""} {
        puts "❌ Respuesta vacía del servidor de licencias"
        exit
    }

    # Parsear respuesta JSON
    if {[catch {set parsed [json::json2dict $response]} err]} {
        puts "❌ Error parseando respuesta JSON: $err"
        puts "🔍 Respuesta recibida: $response"
        exit
    }

    # Verificar que la respuesta tenga la estructura esperada
    if {![dict exists $parsed valid]} {
        puts "❌ Respuesta inválida del servidor. Estructura: $parsed"
        exit
    }

    # Procesar resultado de la validación
    if {[dict get $parsed valid] eq "true"} {
        # Licencia válida
        puts "🎉 ✅ Licencia válida. Bot autorizado para iniciar."
        
        # Mostrar información adicional si está disponible
        if {[dict exists $parsed expires]} {
            set expires [dict get $parsed expires]
            puts "📅 Expira: $expires"
        }
        
        if {[dict exists $parsed reactivated] && [dict get $parsed reactivated] eq "true"} {
            puts "⚡ Licencia reactivada exitosamente"
            if {[dict exists $parsed reactivaciones]} {
                puts "🔢 Reactivaciones: [dict get $parsed reactivaciones]"
            }
        }
        
        puts ""
        return
    } else {
        # Licencia inválida - mostrar mensaje de error
        if {[dict exists $parsed error]} {
            set error_msg [dict get $parsed error]
            puts "❌ Licencia inválida: $error_msg"
        } else {
            puts "❌ Licencia inválida: Error desconocido"
        }
        exit
    }
}

# Ejecutar verificación antes de iniciar el bot
validate_license


### =======================
### CONFIGURACIÓN
### =======================
set tickets_file "tickets.txt"
set ticketslog_file "tickets.log"

set support_channel "#ritmolatinos_help" ;#Canal de ayuda. -> Aquí debes poner el canal de ayuda ejemplo #Opers_help o el canal que tengas de ayuda.
set ops_channel     "#ritmolatinos_ad" ;#Canal administrador. -> Aquí debe poner el canal de operadores o en su efecto el canal administrador.

array set ticket_timers {
    warn       300
    escalate   600
    autoclose  1800
}

set cleanup_interval 300
set ticket_ban_time 300

set max_daily_tickets 5   ;# Número límite de tickets por día
set max_ticket_wait 600   ;# tiempo para que un usuario vuelva antes de eliminar ticket
set akick_time 86400      ;# 24h

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

# Función mejorada para lectura segura de archivos
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
    if {[matchchanattr $nick $chan o]} { return 1 } ;# Op (@)
    if {[matchchanattr $nick $chan h]} { return 1 } ;# Halfop (%)
    if {[matchchanattr $nick $chan a]} { return 1 } ;# Admin (&)
    if {[matchchanattr $nick $chan q]} { return 1 } ;# Owner (~)
    return 0
}

# Función auxiliar para verificar voice
proc is_voiced {nick chan} {
    return [matchchanattr $nick $chan v]
}

# Función para verificar si es operador autorizado
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
### INFORMACIÓN DEL BOT (INICIO SEGURO)
### =======================
set bot_name "IrcHelp"
set bot_version "1.0"
set bot_author "Atómico (Founder)"
set bot_email "r.ritmo.latinos@gmail.com"
set bot_server "irc.chatdetodos.com"
set bot_web "www.ritmolatinoscrc.com"

proc show_bot_info {} {
    global bot_name bot_version bot_author bot_email bot_server bot_web ops_channel

    # Capturar errores para no interrumpir la conexión
    if {[catch {
        # Mostrar en partyline (usando stdout)
        puts "=============================================="
        puts "$bot_name $bot_version - Sistema de Tickets Cargado"
        puts "Autor: $bot_author"
        puts "Email: $bot_email"
        puts "Servidor: $bot_server"
        puts "Web: $bot_web"
        puts "=============================================="

        # Aviso al canal de operadores
        putserv "PRIVMSG $ops_channel : ℹ$bot_name v$bot_version iniciado correctamente."
        
    } err]} {
        # Registrar el error en partyline
        puts "⚠️ Error cargando el script de tickets: $err"
    }
}

### =======================
### AUTO-VOICE PARA USUARIOS
### =======================
set support_channel "#ritmolatinos_help"

# Función que da voice al usuario que entra
proc user_joined {nick uhost hand chan} {
    global support_channel
    if {$chan eq $support_channel} {
        # Verificar que el usuario no tenga ya voice antes de dárselo
        if {![is_voiced $nick $chan]} {
            putserv "MODE $support_channel +v $nick"
            putserv "NOTICE $nick :✅ Bienvenido a $support_channel! Ahora tienes voz para comunicarte. Usa !ticket <mensaje> para que un operador te atienda."
        }
    }
}

# Vincular función al evento JOIN
bind join - * user_joined

### =======================
### COMANDOS BOT
### =======================

# Crear ticket (!ticket <detalle>)
bind pub - "!ticket" create_ticket
proc create_ticket {nick uhost hand chan text} {
    global tickets_file ops_channel support_channel max_daily_tickets akick_time

    # Solo se puede usar en el canal de soporte
    if {$chan ne $support_channel} { 
        putserv "NOTICE $nick :⚠️ Solo puedes crear tickets en $support_channel."
        return 
    }
    
    if {$text eq ""} { 
        putserv "NOTICE $nick :Uso: !ticket <detalle de tu problema>"
        return 
    }

    # Contar tickets diarios del usuario
    set data [read_file_safe $tickets_file]
    set count 0
    foreach line [split $data "\n"] {
        if {$line eq ""} continue
        set parts [split $line ";"]
        set tnick [lindex $parts 1]
        if {$tnick eq $nick} { incr count }
    }

    # Verificar límite diario
    if {$count >= $max_daily_tickets} {
        putserv "NOTICE $nick :❌ Has excedido el límite diario de tickets. Debes esperar 24 horas para crear un nuevo ticket."
        putserv "KICK $support_channel $nick :🚫 Has superado el límite de solicitudes de ayuda. Vuelve en 24h."
        putserv "/cs akick $support_channel add $uhost Has sido sancionado por exceder el límite de solicitudes en $support_channel."
        utimer $akick_time [list putserv ".MSG ChanServ akick $support_channel del $uhost"]
        return
    }

    # Mostrar cuántos tickets le quedan
    set restante [expr {$max_daily_tickets - $count}]
    if {$restante > 0} {
        putserv "NOTICE $nick :ℹ️ Puedes crear $restante ticket(s) más hoy."
    }

    # Crear ticket con ID (timestamp)
    set timestamp [clock seconds]
    set ticket_id $timestamp
    set line "$ticket_id;$nick;[maskhost $uhost];$text;-"
    set fp [open $tickets_file a]
    puts $fp $line
    close $fp

    # Notificaciones
    putserv "NOTICE $nick :✅ Ticket creado (ID $ticket_id). Un operador te atenderá pronto."
	putserv "MODE $support_channel +v $nick"
    putserv "PRIVMSG $ops_channel :✅ Nuevo ticket $ticket_id de $nick → $text"
    putlog "✅ Ticket $ticket_id creado por $nick: $text"
}

# Ver tickets (!tickets) - Versión mejorada
bind pub - "!tickets" show_tickets
proc show_tickets {nick uhost hand chan text} {
    global tickets_file ops_channel

    if {$chan ne $ops_channel} { return }

    set data [read_file_safe $tickets_file]
    if {$data eq ""} {
        putserv "PRIVMSG $ops_channel :❌ No hay tickets abiertos."
        return
    }

    # Filtrar líneas válidas de manera más eficiente
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

    # Mostrar lista
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

# Tomar ticket (!ayuda) - SOLO PARA TOMAR TICKETS
bind pub - "!ayuda" take_ticket
proc take_ticket {opnick uhost hand chan text} {
    global tickets_file ops_channel

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

# Finalizar ticket (!fin) - Versión mejorada
bind pub - "!fin" close_ticket
proc close_ticket {nick uhost hand chan text} {
    global tickets_file ops_channel support_channel ticket_ban_time

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

        # Buscar por ID exacto
        if {$text eq $t_id} {
            set found 1
            set user_to_kick $tnick
            set user_host $thost
            putserv "PRIVMSG $ops_channel :✔ Ticket $t_id de $tnick cerrado."
            putserv "NOTICE $tnick :✅ Tu ticket #$t_id ha sido cerrado por $nick."
            continue
			# Buscar por nick (cierra todos los tickets del usuario)
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

    # Quitar voice y aplicar medidas si se encontró el usuario
    if {$found && $user_to_kick ne ""} {
        # Quitar voice solo una vez
        putserv "MODE $support_channel -v $user_to_kick"
        
        # Solo kickear si se cerraron todos los tickets (por nick)
        if {[string is integer -strict $text]} {
            # Cerrado por ID - solo quitar voice y log
            putlog "Ticket $text cerrado por $nick"
        } else {
			# Cerrado por nick - aplicar BAN + KICK
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

# Revisión automática de tickets - VERSIÓN MEJORADA
proc check_tickets {} {
    global tickets_file ticket_timers ops_channel
    set now [clock seconds]
    set lines [split [read_file_safe $tickets_file] "\n"]
    set cleaned {}
    
    # Array temporal para controlar notificaciones por usuario
    array set notified_users {}

    foreach line $lines {
        if {$line eq ""} continue
        set parts [split $line ";"]
        if {[llength $parts] < 5} { continue }
        
        set t_id [lindex $parts 0]
        set nick [lindex $parts 1]
        set detalle [lindex $parts 3]
        set timestamp [lindex $parts 0]
        set tasign [lindex $parts 4]

        if {[string is integer -strict $timestamp]} {
            set age [expr {$now - $timestamp}]
        } else { 
            set age 0 
        }

        if {$age >= $ticket_timers(autoclose)} {
            putserv "NOTICE $nick :❌ Tu ticket ha sido cerrado automáticamente porque no fue atendido."
            putserv "PRIVMSG $ops_channel :❌ Ticket #$t_id de $nick cerrado automáticamente (sin respuesta)."
            putlog "❌ Ticket $t_id de $nick cerrado automáticamente."
            continue
        }

        if {$age >= $ticket_timers(escalate) && ($tasign eq "-" || $tasign eq "")} {
            putserv "PRIVMSG $ops_channel :ℹ Atención: Ticket #$t_id de $nick lleva 10 minutos pendiente. → $detalle"
        }

        if {$age >= $ticket_timers(warn) && ($tasign eq "-" || $tasign eq "")} {
            # Verificar si ya notificamos a este usuario en esta ejecución
            if {![info exists notified_users($nick)]} {
                # Contar tickets pendientes del usuario
                set user_pending_tickets 0
                foreach check_line $lines {
                    if {$check_line eq ""} continue
                    set check_parts [split $check_line ";"]
                    if {[llength $check_parts] >= 5} {
                        set check_nick [lindex $check_parts 1]
                        set check_tasign [lindex $check_parts 4]
                        if {$check_nick eq $nick && ($check_tasign eq "-" || $check_tasign eq "")} {
                            incr user_pending_tickets
                        }
                    }
                }
                
                # Mensaje personalizado según cantidad de tickets
                if {$user_pending_tickets == 1} {
                    putserv "NOTICE $nick :⏳ Tu solicitud sigue pendiente. Un operador te atenderá pronto."
                } else {
                    putserv "NOTICE $nick :⏳ Tienes $user_pending_tickets solicitudes pendientes. Serás atendido en orden de llegada."
                }
                
                putserv "PRIVMSG $ops_channel :ℹ $nick tiene $user_pending_tickets ticket(s) pendiente(s). Usa !tickets para ver la lista."
                
                # Marcar como notificado en esta ejecución
                set notified_users($nick) 1
            }
        }

        lappend cleaned $line
    }

    write_file $tickets_file [join $cleaned "\n"]
    utimer 300 check_tickets
}

utimer 10 check_tickets

# Autoeliminar tickets si usuario no vuelve
bind part - * user:left
bind sign - * user:left
proc user:left {nick uhost hand chan text} {
    global tickets_file support_channel max_ticket_wait ops_channel
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

# Comando de ayuda (!help) - Versión mejorada y profesional
bind pub - "!help" show_help
# NOTA: !ayuda ya está usado para tomar tickets, así que no lo vinculamos aquí

proc show_help {nick uhost hand chan text} {
    global support_channel ops_channel bot_name
    
    if {$chan eq $support_channel} {
        # Menú para usuarios - Diseño profesional
       
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
        # Menú para operadores - Diseño profesional
        
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
        # Mensaje para canales no autorizados
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
bind pub - "!stats" show_stats  ;# Alias corto

proc show_stats {nick uhost hand chan text} {
    global tickets_file ops_channel support_channel
    
    if {$chan ne $ops_channel} { return }
    
    set data [read_file_safe $tickets_file]
    set total_tickets 0
    set pending_tickets 0
    set assigned_tickets 0
    array set operators {}
    
    # Analizar tickets
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
    
    # Mostrar estadísticas con diseño profesional
    
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
    
    # Mostrar estadísticas por operador si hay tickets asignados
    if {[array size operators] > 0} {
        putserv "PRIVMSG $ops_channel : **Tickets por operador:**                      "
        set count 0
        foreach op [lsort [array names operators]] {
            incr count
            if {$count <= 5} {  # Mostrar máximo 5 operadores
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















