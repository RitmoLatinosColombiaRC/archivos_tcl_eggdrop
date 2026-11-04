# Sistema de Tickets para Eggdrop IRC con Antiflood

Script TCL para Eggdrop que implementa un sistema completo de soporte técnico vía IRC, pensado para canales de ayuda como `#Ayuda`, con gestión de tickets por parte de operadores, protección antiflood y estadísticas del canal.

- **Autor:** Atomico
- **Network IRC:** `irc.ritmolatinoscrc.com` (SSL/TLS: `+6697`, SASL opcional)
- **Web:** https://www.ritmolatinoscrc.com
- **WebChat:** https://webchat.ritmolatinoscrc.com/#ayuda
- **Canal de soporte:** `#Ayuda`

---

## 📜 Licencia

**CÓDIGO VISIBLE GRATUITO CON MODIFICACIÓN RESTRINGIDA**  
*(Source-Available, modificación solo con permiso del autor)*

Copyright (c) **Atomico / Ritmo Latinos Colombia**.  
Todos los derechos reservados.

> **Nota:** Este script se publica como **código visible (source-available)** para que la comunidad pueda usarlo gratuitamente en sus redes. **No es una licencia de código abierto** porque el autor desea mantener el control sobre las modificaciones y evitar su venta. Si deseas proponer una mejora, contacta con Atomico.

El texto legal completo está disponible en el archivo [LICENSE](LICENSE).

### Resumen de la licencia

- ✅ **Uso gratuito** en cualquier red IRC, manteniendo el aviso de copyright.
- ❌ **Prohibida la venta** o distribución comercial (con posibles acciones legales).
- ❌ **Prohibida la modificación** sin permiso escrito del autor.
- ❌ **Prohibida la redistribución** de versiones modificadas.
- 📬 **Contacto para permisos:** `#Ayuda` en `irc.ritmolatinoscrc.com (SSL/TLS: +6697, SASL opcional)`, WebChat o web oficial.

---

## 📖 Descripción del script

Este script convierte a tu Eggdrop en un **sistema de tickets de soporte** para el canal `#Ayuda`. Los usuarios pueden abrir tickets con sus preguntas, consultar el estado de su ticket, reclamarlo si cambiaron de nick, y recibir respuestas de los operadores. Los operadores gestionan los tickets desde un canal de administración (configurable, por defecto `#opers`) con comandos como tomar, responder, cerrar, ver y listar tickets.

Además, incluye:

- **Protección antiflood** por usuario/host para evitar spam de comandos.
- **Persistencia robusta** en disco con escritura atómica (evita corrupción de ficheros).
- **Respuestas pendientes**: si el usuario no está conectado cuando el operador responde, la respuesta se guarda y se entrega automáticamente al reconectarse (con caducidad de 5 minutos y cierre automático si no aparece).
- **Estadísticas del canal `#Ayuda`**: contador de visitas únicas por sesión, listado de usuarios conectados con hora de entrada, y notificaciones de join/part/quit al canal de operadores.

---

## ⚙️ Cómo funciona

### 1. Creación de tickets

Cuando un usuario escribe `!ayuda <pregunta>` (por privado o en canal), el script:

1. Verifica el **antiflood** (máximo de comandos por ventana de tiempo; si se excede, el usuario es silenciado temporalmente).
2. Valida que la pregunta no esté vacía.
3. Genera un **ID alfanumérico único** de 6 caracteres (sin colisiones).
4. Guarda el ticket en `scripts/tickets/ticket_<ID>.txt` con fecha, usuario, estado `ABIERTO`, pregunta e historial inicial.
5. Responde al usuario con el ID y avisa al canal de operadores.

### 2. Consulta de estado

Con `!estado <id>`, el usuario obtiene el estado actual del ticket:

- **ABIERTO**: aún no atendido. Se avisa al canal de operadores si lleva tiempo sin atención.
- **EN PROCESO**: un operador lo está atendiendo. Si ya tiene respuesta, se indica.
- **EN ESPERA**: el usuario no estaba conectado cuando se respondió; tiene 5 minutos para conectarse antes de que se cierre automáticamente.
- **CERRADO**: se muestra el motivo (cerrado por operador, por apelación, o automáticamente por inactividad).

### 3. Apelación de tickets

Si un usuario cambió de nick y quiere reclamar su ticket, puede usar `!apelar <id> [palabra clave]`. El script valida por:

- **Hostmask**: si el host actual coincide con el del ticket original.
- **Palabra clave**: si al menos 4 caracteres de la palabra clave aparecen en la pregunta original.

Si la validación es correcta, el ticket se reasigna al nuevo nick y, si estaba `CERRADO` o `EN ESPERA`, se reabre.

### 4. Gestión por operadores

Desde el canal de administración (por defecto `#opers`), los operadores pueden:

- `!tomar <id>` → Marca el ticket como `EN PROCESO` y avisa al usuario.
- `!responder <id> <mensaje>` → Añade la respuesta al historial. Si el usuario está conectado, se la envía; si no, la guarda como pendiente y pone el ticket en `EN ESPERA`.
- `!cerrar <id>` → Cierra el ticket, avisa al usuario, y tras 30 segundos le aplica un **ban + kick** del canal `#Ayuda` (para liberar el canal).
- `!ticket <id>` → Muestra el ticket completo (sin límite de líneas).
- `!tickets` → Lista los tickets activos (`ABIERTO`, `EN PROCESO`, `EN ESPERA`), máximo 10 por vez.
- `!ticketsall` → Resumen de todos los tickets (activos y cerrados).
- `!help_ticket` → Muestra la ayuda de comandos de operador.

### 5. Respuestas pendientes y cierre automático

Si un operador responde a un ticket cuyo usuario **no está conectado**:

1. La respuesta se guarda en `scripts/tickets/pending_<ID>.txt` con el nick, hostmask, operador, hora y mensaje.
2. El ticket pasa a `EN ESPERA`.
3. Se programa un temporizador de **5 minutos**. Si el usuario se conecta antes, recibe la respuesta automáticamente al entrar al canal (o al hacer `!apelar`). Si no se conecta en 5 minutos, el ticket se **cierra automáticamente** con el motivo "el usuario no se conectó en 5 minutos".

### 6. Antiflood

El script lleva un registro por `nick:host` de los comandos usados en una ventana de tiempo. Por defecto:

- **Máximo 3 comandos** en **10 segundos**.
- Si se excede, el usuario es **silenciado 60 segundos** (no puede usar comandos de ticket).
- Los datos de flood se limpian periódicamente (cada minuto) para no acumular memoria.

Los parámetros son configurables al inicio del script:

```tcl
set flood_max_commands 3
set flood_time_window 10
set flood_punish_time 60
