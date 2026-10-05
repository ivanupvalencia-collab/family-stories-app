# Tus respuestas: instalación manual pendiente

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
