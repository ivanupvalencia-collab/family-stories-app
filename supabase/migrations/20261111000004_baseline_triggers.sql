-- =============================================================================
-- 20261111000004_baseline_triggers.sql
-- Triggers exportados de pg_trigger (2026-11-11). 8 triggers de tabla.
--
-- ADVERTENCIA: el volcado de pg_trigger no incluye los EVENT TRIGGERS (estan
-- en pg_event_trigger). Se recrea aqui 'rls_auto_enable' a partir de su
-- funcion (exportada en 0003) + el CREATE EVENT TRIGGER correspondiente.
-- El nombre exacto del event trigger original no esta exportado; se usa el
-- canonico 'rls_auto_enable'. Si el proyecto remoto usa otro nombre, eliminar
-- este bloque duplicado.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- auth.users -> crea la fila de profiles.
-- La app NUNCA inserta en profiles (verificado: el unico .insert() de lib/
-- es sobre family_members). Sin este trigger el FK de family_members fallaria.
-- ---------------------------------------------------------------------------
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- public.family_members
-- ---------------------------------------------------------------------------
drop trigger if exists family_delete_parent_guard on public.family_members;
create trigger family_delete_parent_guard
  before insert or delete or update on public.family_members
  for each row execute function public.guard_family_delete_parent();

drop trigger if exists family_members_protect_linked_account on public.family_members;
create trigger family_members_protect_linked_account
  before insert or update of linked_account_id on public.family_members
  for each row execute function public.protect_family_member_linked_account();

-- ---------------------------------------------------------------------------
-- public.family_invitations
-- ---------------------------------------------------------------------------
drop trigger if exists family_invitations_set_updated_at on public.family_invitations;
create trigger family_invitations_set_updated_at
  before update on public.family_invitations
  for each row execute function public.set_family_invitation_updated_at();

drop trigger if exists family_delete_child_guard on public.family_invitations;
create trigger family_delete_child_guard
  before insert or delete or update on public.family_invitations
  for each row execute function public.guard_family_delete_child('family_member_id');

-- ---------------------------------------------------------------------------
-- public.question_requests
-- ---------------------------------------------------------------------------
drop trigger if exists family_delete_child_guard on public.question_requests;
create trigger family_delete_child_guard
  before insert or delete or update on public.question_requests
  for each row execute function public.guard_family_delete_child('family_member_id');

-- ---------------------------------------------------------------------------
-- public.stories
-- ---------------------------------------------------------------------------
drop trigger if exists guard_story_photo_path_change on public.stories;
create trigger guard_story_photo_path_change
  before insert or update of photo_path on public.stories
  for each row execute function public.guard_story_photo_path_change();

drop trigger if exists family_delete_child_guard on public.stories;
create trigger family_delete_child_guard
  before insert or delete or update on public.stories
  for each row execute function public.guard_family_delete_child('family_member_id');

-- ---------------------------------------------------------------------------
-- public.profiles / family_member_deletions: sin triggers.
--   * profiles: updated_at NO tiene trigger (S-27). Se conserva fiel.
--   * family_member_deletions: completado solo via finish_family_member_delete.
-- ---------------------------------------------------------------------------
-- NOTA (S-27): tampoco hay set_updated_at en family_members, profiles,
-- stories ni question_requests. Solo family_invitations lo tiene.

-- ---------------------------------------------------------------------------
-- Event trigger: auto-activa RLS en tablas nuevas de public.
-- ---------------------------------------------------------------------------
drop event trigger if exists rls_auto_enable;
create event trigger rls_auto_enable
  on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function public.rls_auto_enable();
