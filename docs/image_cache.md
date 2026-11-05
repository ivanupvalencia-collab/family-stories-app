# Pipeline de imágenes

## Diagnóstico

| Tipo | Memoria anterior | Disco anterior | Espera que provocaba el retraso |
|---|---|---|---|
| Avatar propio subido | Flutter ImageCache + precarga del perfil | No | Tras reiniciar se consultaba `profiles` y se descargaba de nuevo la URL del avatar. |
| Avatar de otra cuenta | Metadatos en VisibleAccountAvatarService + NetworkImage | No | RPC `get_visible_account_avatars` antes de conocer la URL; nueva descarga tras reiniciar. |
| Foto propia de un ser querido | Caché compartida por SupabaseClient | Sí | Home ya recuperaba la lista persistida y precargaba del disco los primeros retratos y el hero. Las restantes se leen al mostrarse. |
| Hero | Reutiliza FamilyMemberPhotoView | Según su origen | Con foto propia aprovechaba el disco; con avatar vinculado tenía las dos esperas anteriores. |
| Foto de historia | Caché compartida por SupabaseClient | Sí | Los bytes ya se reutilizaban. En las miniaturas de Inicio se esperaba además a `get_my_answer_story` para recuperar su referencia. |

Los avatares predefinidos son assets incluidos en la app: no requieren descarga.
Las fotos locales son archivos persistentes de la aplicación y no dependen de Supabase.

## Comportamiento actual

- `ProfileAvatarImageCache` comparte la carga del avatar propio y los avatares visibles de otras cuentas por cliente/backend y sesión. Conserva las imágenes decodificadas en Flutter ImageCache y hasta 24 MiB de bytes en memoria.
- Las imágenes y sus referencias autorizadas se guardan en Application Support usando **RemoteFamilyPhotoDiskCache**, el mismo almacén privado y escritura atómica que ya usan las fotos. No hay una segunda librería de caché ni dependencia nueva.
- Los metadatos conocidos se recuperan primero del disco. `profiles` y la RPC de avatares se validan en segundo plano y notifican cambios a las vistas. Una URL con la misma revisión reutiliza sus bytes: no se descarga otra vez por reiniciar o navegar.
- Los metadatos e imágenes incluyen backend, cuenta que visualiza, cuenta del avatar y URL completa con revisión. Las descargas simultáneas se deduplican. Los archivos vacíos/corruptos se descartan antes de mostrarlos.
- Cambiar/quitar el avatar invalida la referencia y los bytes anteriores. Cambiar de cuenta o hacer logout invalida las tareas pendientes y limpia el espacio de avatares de la cuenta anterior. Cerrar una pantalla no elimina la caché persistente.
- Home también recupera los metadatos conocidos de avatares vinculados al precargar la familia. El hero mantiene la prioridad foto propia → avatar vinculado → fallback.
- Las miniaturas de respuestas de Inicio recuperan su referencia visual y bytes del disco mientras consultan la RPC actual. La referencia se actualiza o elimina al recibir el resultado, al editar la foto o al limpiar sus recursos. Una denegación explícita elimina el resultado cacheado; un fallo transitorio permite conservar la imagen conocida.
- La caché de miniaturas es solo presentación: abrir/reproducir una respuesta sigue utilizando la RPC autorizada existente. Las fotos privadas siguen descargándose mediante Storage autenticado; los avatares usan la URL del bucket `avatars`, que ya era público. Nunca se consulta la foto de Google.

Las fotos privadas de familia/historias mantienen sus namespaces por backend/cuenta, referencias inmutables, limpieza al sustituir/eliminar y protección de generación frente a cambios de sesión. Con una referencia conocida, la lectura empieza en memoria/disco; Storage solo se consulta si faltan bytes válidos. La carga inicial de listas/historias continúa usando sus servicios actuales: esta mejora no añade un modo offline general ni evita las consultas de autorización.

## Prueba manual

1. Con sesión, mostrar Perfil, preguntas recibidas, familia, hero e historias con foto. Esperar a su primera carga.
2. Forzar el cierre de la app sin cerrar sesión. Abrir de nuevo con red lenta o sin red: las referencias e imágenes ya conocidas deben recuperarse del almacenamiento local; las listas no cacheadas pueden seguir necesitando red.
3. Abrir y cerrar Perfil repetidamente. Verificar que no se vuelve a descargar la misma revisión.
4. Restablecer la red. Cambiar/quitar un avatar o foto y verificar que la nueva referencia aparece y no revive la anterior tras otro reinicio.
5. Cerrar sesión y entrar con otra cuenta. Comprobar que no aparece ninguna imagen de la sesión anterior.

Pruebas automatizadas: persistent_avatar_cache_test, profile_avatar_image_cache_test, visible_account_avatar_service_test, family_member_photo_service_test, story_photo_service_test y home_answer_preview_test cubren disco tras reinicio, servidor bloqueado, deduplicación, aislamiento, corrupción, cambios de revisión, eliminación y descargas tardías.
