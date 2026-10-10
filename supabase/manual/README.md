# Tus respuestas: instalación manual pendiente

## Espacio del ser querido y fotos de historias

Scripts nuevos preparados, **no ejecutados**. Con las fotos de FamilyMember ya
instaladas (01 y 02), ejecutar completos en este orden:

1. `03_story_photos.sql`: columna nullable, bucket privado `story-photos`,
   límite de 10 MB, MIME de imagen y políticas específicas por historia.
2. `04_story_photo_rpc.sql`: lectura y edición acotadas al propietario del
   familiar o `recorded_by`; actualiza `get_my_answer_story` para devolver foto.
   No volver a instalar la versión anterior de esa RPC después de este script.
3. `05_family_member_edit.sql`: edición de nombre/relación por el propietario,
   sin modificar vinculación, fotos ni ampliar UPDATE de la tabla.
4. `06_family_member_delete_audit.sql` es una consulta **de diagnóstico**, no
   habilita eliminación. Puede ejecutarse después para revisar FKs y políticas.

La app mantiene la eliminación remota bloqueada: el esquema base y las FKs de
invitaciones no están versionados aquí. Falta revisar esos resultados y diseñar
el borrado coordinado con la API de Storage. No borrar `storage.objects` por SQL:
eso no elimina correctamente los archivos físicos. La eliminación local pide
confirmación, retira las referencias y limpia los archivos de su espacio privado.

Las fotos se suben con nombres únicos `<uploader-id>/<story-id>/<filename>`.
El propietario y el autor pueden consultar/cambiar la foto de esa historia;
una cuenta ajena y anon no pueden acceder. Storage exige la relación con la
historia real. La foto activa no se puede borrar: primero se confirma la nueva
referencia o NULL por RPC, después se limpia la anterior. No hay URLs públicas,
UPDATE de objetos ni modificaciones de políticas existentes de audio/perfiles.

La respuesta remota completa primero `complete_question_request`, con su
contrato actual, y usa el ID devuelto para asociar después la foto. Si la foto
falla, el audio sigue guardado; se puede añadir desde Historia/Tus respuestas.
Antes de instalar SQL, las historias antiguas mantienen audio (fallback sólo
ante columna ausente) y la edición de fotos remotas no está disponible.

Verificar con sesiones reales de propietario, autor y tercero: lectura,
subida, reemplazo y eliminación; el tercero debe recibir denegación, así como
las rutas de otra historia o subidas fuera de su namespace. Intentar borrar una
foto activa debe fallar. Las pruebas Flutter simulan HTTP y no ejecutan ni
certifican las políticas del proyecto Supabase.

---

Ejecutar `get_my_answer_story.sql` completo en el SQL Editor de Supabase con
el rol administrativo habitual (`postgres`). **No se ha ejecutado desde este
repositorio.** El contrato supone identificadores UUID, como las RPC existentes.

La lista usa el SELECT existente de `question_requests`; funciona sin esta RPC.
Abrir y reproducir una respuesta requiere instalarla. Si falta, la pantalla
muestra un error recuperable; no intenta leer `stories` directamente ni usar
URLs públicas. Las secciones de pendientes y familiares siguen funcionando.

La RPC retorna únicamente los metadatos necesarios de una respuesta concreta.
No acepta un usuario como parámetro: obtiene su identidad mediante `auth.uid()`.
Exige solicitud `answered`, destinatario autenticado, autor de la grabación
coincidente y la misma relación solicitud/familiar. Solicitudes inexistentes,
pendientes o de otra persona devuelven `null` sin revelar su existencia.
`SECURITY DEFINER` permite obtener esos metadatos pese a la RLS de `stories`
orientada al propietario. El `search_path` es vacío, las tablas se califican
con su esquema y el acceso anónimo se revoca. No se modifica ninguna RLS,
tabla ni política de Storage.

El audio se descarga mediante la sesión del destinatario y la política SELECT
ya existente de `story-audio`, usando el `audio_path` guardado en la historia.
No se lista Storage ni se reconstruye el nombre del objeto.

## Verificación manual

1. Con Pepe, comprobar la lista, las fechas y la reproducción de una respuesta
   anterior (también tras reiniciar la app).
2. Responder una pregunta nueva: desaparece de pendientes y aparece en
   respuestas al volver a Home. Comprobar también pull-to-refresh y Realtime.
3. Con Iván, verificar el flujo original y su reproducción en el perfil de Pepe.
4. Con una sesión autenticada de Pepe, invocar la RPC con el ID de su solicitud
   respondida: debe devolver la historia. Con otra cuenta (incluido Iván), ese
   mismo ID debe devolver `null`. Pendientes e IDs inexistentes también deben
   devolver `null`. Anónimo no debe tener EXECUTE. Probar mediante sesiones
   reales/Data API: el SQL Editor administrativo no reproduce la RLS del usuario.
5. Cambiar de cuenta o cerrar sesión: no deben quedar respuestas de Pepe en Home
   ni reproducirse una respuesta abierta desde su sesión anterior.

Las pruebas Flutter utilizan un servidor local simulado: verifican el contrato
HTTP, estado y reproducción, pero no certifican la RLS del proyecto remoto ni
la RPC instalada. La verificación anterior sigue siendo necesaria.
