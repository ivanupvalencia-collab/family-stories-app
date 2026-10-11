# Fotos propias de FamilyMember

## Instalación manual obligatoria para el flujo remoto

Estos scripts **no se han ejecutado** contra Supabase. Antes de probar esta
versión con sesión, ejecutarlos completos en el SQL Editor como `postgres`,
en este orden:

1. `01_family_member_photos.sql`: añade `family_members.photo_path` nullable,
   comprueba que la ruta pertenece al propietario y al familiar, crea el bucket
   privado `family-member-photos` y las políticas Storage de lectura, subida,
   sustitución y eliminación. Incluye restricciones para que otras políticas
   permisivas antiguas no concedan acceso a este bucket a terceros o anónimos.
2. `02_family_member_photo_rpc.sql`: instala `set_family_member_photo` para
   actualizar solamente esa referencia. Requiere sesión, comprueba el
   propietario, la ruta y la existencia del objeto. La referencia anterior
   debe coincidir para evitar que dos dispositivos sobrescriban sus cambios.

No volver a ejecutar `get_my_answer_story.sql` para esta funcionalidad. No se
modifican políticas de `avatars`, `story-audio`, invitaciones, autenticación ni
`stories`. No se desactiva RLS ni se concede UPDATE general sobre
`family_members`. La RPC usa `SECURITY DEFINER` con `search_path` vacío,
esquemas explícitos y sin EXECUTE anónimo; su identidad procede de `auth.uid()`.

Los SELECT remotos de familiares incluyen el campo nuevo: **el primer script
es necesario antes de usar esta versión con sesión**. Sin el segundo, se pueden
leer familiares pero no guardar/eliminar su foto. No hay migración de fotos de
cuentas vinculadas ni de `profiles`. Las filas existentes conservan
`photo_path = NULL` y sus datos actuales.

## Almacenamiento y sustitución

- Local: bytes del selector copiados con `flush` al directorio privado
  persistente de soporte de la app. SharedPreferences guarda una ruta relativa
  `family_member_photos/<memberId>/<revision>.<extension>`; no se guarda la ruta
  temporal de la galería. Una referencia relativa tolera cambios de la ruta
  del contenedor de la app. Los registros antiguos sin campo siguen cargando.
- Remoto: `family-member-photos/<ownerId>/<memberId>/<revision>.<extension>`.
  En la tabla se almacena únicamente la ruta del objeto, sin URL pública ni
  URL firmada. Las lecturas usan `download()` con la sesión del propietario.
- Se admiten JPEG, PNG, WebP, HEIC/HEIF de hasta 10 MB. La visualización utiliza
  los decodificadores de Flutter del dispositivo; si un formato no puede
  decodificarse, el componente muestra el fallback neutro.
- Cambiar: escribir/subir archivo nuevo, persistir referencia y solo entonces
  eliminar el anterior. Fallos confirmados de persistencia eliminan el archivo
  preparado y conservan el anterior. Ante una respuesta remota ambigua, se
  confirma el estado antes de borrar; si no puede confirmarse, se conserva el
  objeto para no borrar una foto activa. Limpieza posterior fallida es de mejor
  esfuerzo y puede dejar un objeto huérfano, sin romper la referencia activa.
- Eliminar: persistir NULL y después borrar el objeto/archivo previo. Las
  eliminaciones de archivos están limitadas al directorio del propio familiar.
- Si falla la foto opcional al crear, el familiar se conserva una sola vez,
  sin foto, con aviso para volver a añadirla desde el perfil.

`FamilyMemberPhotoService` y `FamilyMemberPhotoView` son los puntos reutilizables
para próximas pantallas. El widget muestra fallback mientras carga, si falta
la foto o si falla la lectura/decodificación. Si no hay foto propia, puede
mostrar el avatar vinculado únicamente como fallback de visualización,
mediante la RPC limitada de `08_visible_account_avatars.sql` (ver
`ACCOUNT_AVATARS.md`). Nunca lo persiste como foto del familiar.
No hay caché global de bytes privados compartida entre cuentas.

## Prueba manual sin sesión

1. Cerrar sesión. Crear un familiar sin foto y comprobar nombre y relación.
2. Crear otro usando «Elegir foto (opcional)». Seleccionar una imagen y guardar.
   Abrir el familiar: debe aparecer su foto.
3. Cerrar completamente y reabrir la app. La foto y los datos deben seguir.
   Para verificar que no depende de la galería, borrar la imagen original de
   la galería o probar tras limpiar únicamente la caché temporal de la app
   (no borrar los datos persistentes).
4. En el perfil, pulsar el icono de cámara «Foto del familiar» y «Elegir foto de
   la galería»: cambiarla y volver a abrir el perfil. Cancelar el selector
   debe mantener la foto anterior.
5. Usar el mismo menú → «Eliminar foto». Comprobar fallback, reabrir la app y
   comprobar que no reaparece. Si se inspecciona el sandbox de la app, el
   archivo anterior debe haberse eliminado tras una operación satisfactoria.

## Prueba manual con sesión

1. Ejecutar los dos scripts en orden. Con Iván, abrir familiares existentes:
   deben mantener datos y vínculos, con fallback si no tienen foto.
2. Crear un familiar con foto y otro sin ella. En Supabase, comprobar bucket
   privado, ruta `<Iván>/<familyMemberId>/...` y columna `photo_path` correcta.
3. Abrir el perfil, cambiar y eliminar la foto. Confirmar que se actualiza la
   columna y se elimina el objeto anterior al completar la operación. Cerrar
   y reabrir la app; probar también otro dispositivo con la misma cuenta.
4. Elegir una foto propia para un familiar vinculado a Pepe. Cambiar el avatar
   de la cuenta de Pepe: la foto del familiar creado por Iván debe mantenerse.
5. Con una sesión real de Pepe/u otra cuenta, intentar por la Data API descargar,
   subir, reemplazar o eliminar el objeto de Iván, y llamar a la RPC con el ID
   del familiar de Iván: las operaciones deben rechazarse. Repetir lectura sin
   sesión. No probar RLS con una clave service-role ni con el SQL Editor como
   postgres, que tienen privilegios distintos de una sesión de usuario.
6. Cerrar sesión o cambiar de cuenta con el perfil abierto: se oculta la foto
   remota y se deshabilita su edición. No deben mostrarse bytes de la cuenta
   anterior. Volver a entrar y abrir el perfil de nuevo.
7. Repetir Iván → pregunta a Pepe → respuesta → reproducción, «Tus respuestas»
   e invitaciones para comprobar los flujos anteriores.

Las pruebas automatizadas validan archivos, SharedPreferences, contrato HTTP
simulado y widgets. No ejecutan ni certifican la RLS o la RPC del proyecto remoto.
