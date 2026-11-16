-- =============================================================================
-- 20261115000001_avatar_delete_policy.sql
-- S-29: el bucket avatars no tenia politica DELETE.
--
-- Estado actual: ausencia de politica = deny (fail-closed), asi que NO hay
-- agujero: nadie puede borrar objetos de avatars. El problema es de
-- retencion: la app sube a la ruta fija <uid>/profile.<ext> con upsert, pero
-- al revertir a un avatar de catalogo (avatarUrl = null) el objeto anterior
-- queda como huérfano y, al ser el bucket PUBLICO, sigue accesible para
-- siempre.
--
-- Politica own-folder, identica en patron a las 3 existentes de avatars
-- en 0002 (select/insert/update): solo el propietario de la carpeta puede
-- borrar su objeto. La app todavia no llama a remove() en este bucket;
-- esta politica habilita ese borrado cuando se decida implementarlo.
--
-- Solo creacion de archivo: NO aplicar a produccion sin revision.
-- =============================================================================

drop policy if exists "Users can delete their own avatar" on storage.objects;
create policy "Users can delete their own avatar"
  on storage.objects for delete
  to authenticated
  using ((bucket_id = 'avatars'::text)
    and ((storage.foldername(name))[1] = ((select auth.uid())::text)));
