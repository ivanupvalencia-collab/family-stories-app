# Metadatos opcionales para la Home de Aritoria

Ejecuta manualmente `get_received_request_details.sql` en el SQL Editor de Supabase.
Es independiente de los scripts anteriores; no necesitas volver a ejecutarlos.
La app no ejecuta este SQL. La reproducción existente sigue usando
`get_my_answer_story`, ya instalado para «Tus respuestas».

El servicio actual de `profiles` consulta el perfil del propio usuario. Tener
`sender_id` en `question_requests` no concede SELECT al perfil del remitente;
la nueva interfaz no presupone ese permiso ni consulta todos los perfiles.

La RPC devuelve únicamente `request_id`, nombre del remitente y duración de la
última respuesta grabada por el recipient. Comprueba `auth.uid()` contra
`question_requests.recipient_id` dentro de la función SECURITY DEFINER.
No devuelve email, avatares, audio_path ni otros datos del perfil o story.
La duración exige también el mismo family_member y recorded_by; no cambia
las políticas de tablas o Storage. El search_path está vacío y EXECUTE solo se
concede a authenticated. Las solicitudes ajenas o inexistentes no devuelven filas.
Cada lote está limitado a 100 IDs; el servicio divide los historiales grandes.

Si todavía no está instalada, falta el perfil o no tiene nombre, se muestra
«Para quien te preguntó» y se omite la duración desconocida. Las preguntas,
respuestas, Realtime y reproducción siguen disponibles.

Comprobación manual: con Pepe autenticado, los IDs de solicitudes recibidas por
Pepe deben devolver el nombre de su remitente. Los IDs de solicitudes recibidas
por otra cuenta deben devolver cero filas. Prueba después Inicio → Preguntas →
Historias que has contado y abre una respuesta para verificar el audio existente.
