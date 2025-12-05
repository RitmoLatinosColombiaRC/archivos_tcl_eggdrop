#------------------------------------------------------------#
#        🎟️ Sistema de Validación de Licencia - v2.1        #
#------------------------------------------------------------#
# Autor: Atómico (Founder)
# Versión: 2.1
# Email: r.ritmo.latinos@gmail.com
#
# 📌 Descripción:
# Sistema de validación de licencia profesional CORREGIDO
# y optimizado para Eggdrop.
#------------------------------------------------------------#

package require json
package require Tcl 8.6

namespace eval license {
    variable license_file "scripts/license.txt"
    variable validation_passed 0
    variable license_data ""
    variable integrity_verified 0
    
    # Configuración de timeout y reintentos
    variable validation_timeout 15  ;# 15 segundos para curl
    variable max_retries 3
    
    # 🔒 Lista de procedimientos críticos que deben existir
    variable required_procs {
        create_ticket show_tickets take_ticket close_ticket 
        check_tickets show_help show_stats show_system_info
        user_joined user_left check_user_reconnected 
        remove_specific_ticket remove_unassigned_user_tickets
    }
    
    # Lee el contenido de un archivo con manejo de errores
    proc read_file {filename} {
        if {![file exists $filename]} { 
            throw FILE_NOT_FOUND "Archivo no encontrado: $filename"
        }
        
        if {[file size $filename] > 1048576} {  ;# 1MB max
            throw FILE_TOO_LARGE "Archivo demasiado grande: $filename"
        }
        
        set fp [open $filename r]
        set data [read $fp]
        close $fp
        return $data
    }

    # Escribe datos en archivo con backup automático
    proc write_file {filename data} {
        # Crear backup si el archivo existe
        if {[file exists $filename]} {
            file copy -force $filename "$filename.backup_[clock seconds]"
        }
        
        set fp [open $filename w]
        puts -nonewline $fp $data
        close $fp
    }

    # Extrae el valor de cada campo del archivo de licencia
    proc get_license_value {data key} {
        if {[regexp "$key=\\s*(\[^\\r\\n\]+)" $data -> value]} {
            set value [string trim $value]
            # Validar caracteres seguros
            if {[regexp {[<>\"'&;|]} $value]} {
                throw INVALID_CHARS "Caracteres inválidos en valor: $key"
            }
            return $value
        }
        return ""
    }

    # Valida formato de email
    proc validate_email {email} {
        return [regexp {^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$} $email]
    }

    # Valida formato de license key (64 caracteres hex)
    proc validate_license_key {key} {
        return [regexp {^[a-fA-F0-9]{64}$} $key]
    }

    # Codificación URL segura
    proc url_encode {str} {
        set encoded ""
        foreach char [split $str ""] {
            scan $char %c ascii
            if {$ascii < 48 || ($ascii > 57 && $ascii < 65) || 
                ($ascii > 90 && $ascii < 97) || $ascii > 122} {
                append encoded [format "%%%02X" $ascii]
            } else {
                append encoded $char
            }
        }
        return $encoded
    }

    # Validación remota con curl (compatible con Eggdrop)
    proc perform_remote_validation {email key botid attempt} {
        variable validation_timeout
        
        # Codificar parámetros
        set email_enc [url_encode $email]
        set key_enc   [url_encode $key]
        set botid_enc [url_encode $botid]

        # Construir URL de validación
        set base_url "https://script.google.com/macros/s/AKfycbwY0eL8VGeV0XQCs-oEjiffG9QBGWEIH5Nipe3KjeGfOCPo31I36N1ZAvi5XuPeuAaP/exec"
        set url "${base_url}?action=validate&email=${email_enc}&license=${key_enc}&botid=${botid_enc}&attempt=${attempt}"

        puts "🔗 Conectando a: [string range $url 0 100]..."
        
        # Usar curl externo (compatible con Eggdrop)
        if {[catch {
            set response [exec curl -s -L --max-time $validation_timeout $url]
        } error]} {
            throw NETWORK_ERROR "Error de conexión con curl: $error"
        }

        if {$response eq ""} {
            throw EMPTY_RESPONSE "Respuesta vacía del servidor"
        }

        # Parsear JSON de forma segura
        if {[catch {set parsed [json::json2dict $response]} error]} {
            throw JSON_ERROR "Error parseando JSON: $error\nRespuesta: $response"
        }

        # Validar estructura de respuesta
        if {![dict exists $parsed valid]} {
            throw INVALID_RESPONSE "Respuesta inválida del servidor: $parsed"
        }

        # Procesar resultado
        if {[dict get $parsed valid] eq "true"} {
            puts "🎉 ✅ Licencia válida"
            
            # Mostrar información adicional
            if {[dict exists $parsed expires]} {
                set expires [dict get $parsed expires]
                puts "📅 Fecha de expiración: $expires"
            }
            
            if {[dict exists $parsed type]} {
                set type [dict get $parsed type]
                puts "📦 Tipo de licencia: $type"
            }
            
            if {[dict exists $parsed reactivated] && [dict get $parsed reactivated] eq "true"} {
                puts "⚡ Licencia reactivada exitosamente"
            }
            
            return 1
        } else {
            set error_msg [dict get $parsed error]
            puts "❌ Licencia inválida: $error_msg"
            return 0
        }
    }

    # Espera segura compatible con Eggdrop
    proc safe_wait {milliseconds} {
        set end_time [expr {[clock milliseconds] + $milliseconds}]
        while {[clock milliseconds] < $end_time} {
            # Espera activa compatible
            after 100
        }
    }

    # Verificación de licencia con reintentos
    proc validate_license {} {
        variable license_file
        variable validation_passed
        variable license_data
        variable max_retries
        
        puts "🔍 Iniciando verificación de licencia profesional v2.1..."
        
        # Leer y validar archivo de licencia
        if {[catch {
            set license_data [read_file $license_file]
        } error]} {
            puts "❌ Error leyendo archivo de licencia: $error"
            exit 1
        }

        # Extraer y validar campos
        set email [get_license_value $license_data "email"]
        set key   [get_license_value $license_data "key"]
        set botid [get_license_value $license_data "botid"]

        if {$email eq "" || $key eq "" || $botid eq ""} {
            puts "❌ Archivo de licencia incompleto o corrupto"
            exit 1
        }

        # Validaciones de formato
        if {![validate_email $email]} {
            puts "❌ Formato de email inválido: $email"
            exit 1
        }

        if {![validate_license_key $key]} {
            puts "❌ Formato de license key inválido (debe ser 64 caracteres hex)"
            exit 1
        }

        puts "📧 Email: $email"
        puts "🔑 Key: [string range $key 0 7]...[string range $key 56 end]"
        puts "🤖 BotID: $botid"
        puts ""

        # Realizar validación con reintentos
        set success 0
        for {set attempt 1} {$attempt <= $max_retries} {incr attempt} {
            puts "🌐 Intento $attempt de $max_retries..."
            
            if {[catch {
                set success [perform_remote_validation $email $key $botid $attempt]
            } error]} {
                puts "⚠️  Error en intento $attempt: $error"
                if {$attempt < $max_retries} {
                    puts "⏳ Esperando 2 segundos antes del próximo intento..."
                    safe_wait 2000  ;# Esperar 2 segundos entre intentos
                }
            } else {
                if {$success} {
                    break
                }
            }
        }

        if {!$success} {
            puts "❌ No se pudo validar la licencia después de $max_retries intentos"
            exit 1
        }

        set validation_passed 1
        puts "✅ Licencia validada exitosamente"
    }

    # Verificación de integridad mejorada
    proc verify_tickets_script_integrity {} {
        variable required_procs
        variable integrity_verified
        
        set tickets_script "scripts/tickets_system.tcl"
        
        puts "🔍 Verificando integridad del script de tickets..."
        
        if {![file exists $tickets_script]} {
            throw MISSING_SCRIPT "No se encontró el script: $tickets_script"
        }

        # Verificar tamaño del archivo
        set size [file size $tickets_script]
        if {$size < 1000 || $size > 50000} {  # Entre 1KB y 50KB
            throw SUSPICIOUS_SIZE "Tamaño de archivo sospechoso: ${size} bytes"
        }

        # Leer y verificar contenido
        set content [read_file $tickets_script]
        
        # Verificar firma de autor
        if {![string match "*Atómico*" $content] && ![string match "*r.ritmo.latinos*" $content]} {
            throw AUTHOR_MISMATCH "Firma de autor no encontrada"
        }

        # Verificar procedimientos requeridos
        set missing_procs {}
        foreach proc_name $required_procs {
            if {![regexp "proc\\s+$proc_name" $content]} {
                lappend missing_procs $proc_name
            }
        }

        if {[llength $missing_procs] > 0} {
            throw MISSING_PROCS "Procedimientos faltantes: [join $missing_procs {, }]"
        }

        # Verificar que no haya código sospechoso
        set suspicious_patterns {
            {exec\\s+rm\\s+-rf} {system\\s+} {fork\\s+} {eval\\s+\\$}
        }
        
        foreach pattern $suspicious_patterns {
            if {[regexp -nocase $pattern $content]} {
                throw SUSPICIOUS_CODE "Código sospechoso detectado: $pattern"
            }
        }

        set integrity_verified 1
        puts "✅ Integridad del script verificada exitosamente"
        return 1
    }

    # Verificar que la validación fue exitosa
    proc is_validated {} {
        variable validation_passed
        variable integrity_verified
        return [expr {$validation_passed && $integrity_verified}]
    }

    # Obtener información de la licencia
    proc get_license_info {} {
        variable license_data
        if {$license_data eq ""} { return {} }
        
        return [list \
            email [get_license_value $license_data "email"] \
            botid [get_license_value $license_data "botid"] \
        ]
    }
}

# Manejo profesional de errores durante la carga
if {[catch {
    puts "=============================================="
    puts "🔒 SISTEMA DE VALIDACIÓN DE LICENCIA v2.1"
    puts "=============================================="
    
    license::validate_license
    license::verify_tickets_script_integrity
    
    puts ""
    puts "=============================================="
    puts "✅ VALIDACIÓN COMPLETADA EXITOSAMENTE"
    puts "✅ Integridad del sistema verificada"
    puts "✅ Licencia: Premium v2.1"
    puts "✅ Hora: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    puts "=============================================="
    
} error]} {
    puts ""
    puts "=============================================="
    puts "❌ ERROR CRÍTICO DURANTE LA VALIDACIÓN"
    puts "❌ $error"
    puts "=============================================="
    
    # Log detallado del error
    if {[info exists ::errorInfo]} {
        puts "🔍 Stack trace:"
        puts $::errorInfo
    }
    
    exit 1
}

