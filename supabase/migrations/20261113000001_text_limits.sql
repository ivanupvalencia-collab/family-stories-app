-- =============================================================================
-- 20261113000001_text_limits.sql
-- S-13: limite superior de family_members.name.
--
-- El alta de familiar usa INSERT directo sobre family_members
-- (family_member_service.dart), sin pasar por la RPC edit_family_member_info
-- que ya valida length(p_name) <= 200. Sin este CHECK el servidor acepta
-- nombres de cualquier longitud por esa via (el maxLength de la UI es solo
-- cosmético). question_text ya tiene su limite desde 0007.
--
-- Se anyade como NOT VALID para no romper con filas historicas que pudieran
-- superar el limite, y luego se valida: si VALIDATE falla por datos
-- historicos, el constraint sigue protegiendo escrituras nuevas.
--
-- Solo creacion de archivo: NO aplicar a produccion sin revision.
-- =============================================================================

alter table public.family_members
  drop constraint if exists family_members_name_max_length;
alter table public.family_members
  add constraint family_members_name_max_length
  check (char_length(name) <= 200) not valid;

do $$
begin
  alter table public.family_members
    validate constraint family_members_name_max_length;
exception
  when check_violation then
    raise notice 'family_members_name_max_length: filas historicas superan 200 chars; constraint queda NOT VALID pero protege escrituras nuevas';
end $$;
