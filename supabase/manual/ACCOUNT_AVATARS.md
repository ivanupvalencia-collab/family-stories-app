# Avatares visibles de cuentas

Ejecutar manualmente `08_visible_account_avatars.sql` en Supabase SQL Editor
con el rol administrativo habitual, después de los scripts ya instalados.
No se ha ejecutado desde la app ni desde este repositorio.

La RPC devuelve solo id, nombre, avatar_key y avatar_url. Usa auth.uid() y
relaciones comprobadas en la BD: propietario de un FamilyMember vinculado,
o destinatario de una pregunta pendiente enviada por esa cuenta. Los IDs
del cliente solo filtran; nunca autorizan. Máximo 100 IDs por consulta,
search_path vacío, sin acceso anónimo y sin ampliar SELECT/RLS de profiles.
No modifica Storage, tablas, ni RPC existentes.

Se reutilizan los avatares actuales: imágenes del catálogo o avatar_url
del sistema de perfiles (bucket avatars existente). Las fotos propias
siguen usando family-member-photos privado y su caché anterior. Nunca se
escribe el avatar de una cuenta en FamilyMember.photoPath.

Sin instalar 08, o ante errores, la app conserva iniciales/fallbacks.
La nueva caché de metadatos es de sesión, comparte cargas concurrentes
y se limpia al cambiar de cuenta/cerrar sesión; descarta respuestas tardías.
Las imágenes de avatar reutilizan Image.network y la caché de Flutter.

## Prueba manual

1. Instalar únicamente 08; iniciar sesión de nuevo/reiniciar la app.
2. Claudia envía una pregunta a Pepe. Pepe ve en Home su avatar a la
   izquierda, pregunta, remitente/fecha y chevron. Pulsar sigue abriendo
   la respuesta. Probar tanto foto subida como avatar de catálogo.
3. Con una cuenta sin avatar, comprobar su inicial; si una imagen falla,
   también debe aparecer la inicial sin bloquear la pregunta.
4. Iván abre un familiar vinculado a Pepe sin foto propia: se muestra
   el avatar de Pepe en Home y en el perfil. Añadir foto propia: tiene
   prioridad. Eliminarla: vuelve el avatar de Pepe. Sin vinculación ni
   avatar: se conserva el fallback anterior. Probar también sin sesión.
5. Navegar Home/perfil y cerrar sesión/cambiar de cuenta: no debe mostrarse
   el avatar de una sesión anterior durante la nueva carga.
6. Con sesiones reales/Data API, la RPC debe devolver [] para cuentas
   ajenas, y no permitir EXECUTE anónimo. Probar propietario vinculado y
   destinatario de pendiente. El SQL Editor administrativo no simula RLS.

Los tests usan servicios/HTTP simulados; no verifican la instalación ni
las políticas reales de Supabase.
