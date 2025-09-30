#------------------------------------------------------------#
#        🎟️ Sistema de Validación de Licencia              #
#------------------------------------------------------------#
# Autor: Atómico (Founder)
# Versión: 1.0
# Email: r.ritmo.latinos@gmail.com
#
# 📌 Descripción:
# Sistema de validación de licencia para el bot de tickets
# Debe cargarse antes que cualquier otro script
#------------------------------------------------------------#

package require json
package require Tcl 8.5

namespace eval license {
    variable license_file "scripts/license.txt"
    variable validation_passed 0
    
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

    # Verifica si la validación de licencia fue exitosa
    proc is_validated {} {
        variable validation_passed
        return $validation_passed
    }

    # Procedimiento principal de validación de licencia
    proc validate_license {} {
        variable license_file
        variable validation_passed

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
        puts "🤖 BotID: $botid"
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
            set validation_passed 1
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

    # Función para verificar que el script de tickets no ha sido modificado
    proc verify_tickets_script_integrity {} {
        set tickets_script "scripts/tickets_system.tcl"
        
        if {![file exists $tickets_script]} {
            puts "❌ No se encontró el script de tickets: $tickets_script"
            return 0
        }
        
        # Leer el contenido del script de tickets
        set content [read_file $tickets_script]
        
        # Verificar que contiene las funciones principales
        set required_procs {
            create_ticket
            show_tickets
            take_ticket
            close_ticket
            check_tickets
        }
        
        foreach proc_name $required_procs {
            if {![string match "*proc $proc_name*" $content]} {
                puts "❌ Integridad del script comprometida: Falta $proc_name"
                return 0
            }
        }
        
        puts "✅ Integridad del script de tickets verificada"
        return 1
    }
}

# Ejecutar verificación al cargar el script
license::validate_license

# Verificar integridad del script de tickets
if {![license::verify_tickets_script_integrity]} {
    puts "❌ El script de tickets ha sido modificado o está corrupto"
    exit
}

puts "=============================================="
puts "✅ Validación de licencia COMPLETADA"
puts "✅ Scripts verificados y listos para cargar"
puts "✅ Version de licencia 1.0"
puts "=============================================="
