-- =============================================================================
-- 20261114000001_updated_at_triggers.sql
-- S-27: updated_at sin trigger.
--
-- Solo family_invitations tenia trigger de updated_at (exportado de
-- pg_trigger en 0004). El resto de escrituras no actualizaban el campo:
--   * profile_service.dart actualiza profiles por PostgREST directo.
--   * edit_family_member_info y set_family_member_photo actualizan
--     family_members sin tocar updated_at.
--   * Solo accept_family_invitation lo hacia a mano (0003).
-- La app no lee updated_at: la correccion es higiene de datos/auditoria.
--
-- Alcance (decision registrada): solo tablas que YA tienen la columna.
--   * profiles y family_members -> triggers nuevos (este archivo).
--   * family_invitations        -> ya lo tiene (0004, se conserva).
--   * stories y question_requests -> NO tienen columna updated_at
--     (el informe las contaba entre las "4 tablas"); fuera de alcance.
--
-- Funcion generica propia; set_family_invitation_updated_at queda intacta.
--
-- Solo creacion de archivo: NO aplicar a produccion sin revision.
-- =============================================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

revoke all on function public.set_updated_at() from public, anon, authenticated;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

drop trigger if exists family_members_set_updated_at on public.family_members;
create trigger family_members_set_updated_at
  before update on public.family_members
  for each row execute function public.set_updated_at();
