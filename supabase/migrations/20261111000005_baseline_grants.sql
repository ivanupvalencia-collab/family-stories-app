-- =============================================================================
-- 20261111000005_baseline_grants.sql
-- Grants de tabla exportados de information_schema.role_table_grants (2026-11-11)
-- + configuracion de buckets exportada de storage.buckets.
--
-- HALLAZGOS QUE ESTE EXPORT CONFIRMA:
--   S-24  anon y authenticated tienen TRUNCATE sobre 4 tablas. TRUNCATE no
--         esta cubierto por RLS. PostgREST no lo expone hoy, pero viola
--         minimo privilegio. La revocacion esta en 0007.
--   S-30  authenticated NO tiene ningun grant sobre family_invitations ni
--         family_member_deletions => la politica "Inviters can view their own
--         invitations" (0002) nunca se evalua. Politica muerta, inofensiva.
--   S-23  buckets story-audio y avatars sin allowed_mime_types ni
--         file_size_limit. Corregido en 0007.
--   NOTA  service_role solo tiene REFERENCES/TRIGGER/TRUNCATE (sin DML).
--         Inusual pero no es un riesgo: la app no usa service_role (no hay
--         clave service_role en el repositorio).
--
-- NOTA DE DISENO: las politicas de family_members/profiles/stories usan
-- 'to public' (0002) y aqui anon NO recibe DML => el efecto neto es correcto.
-- La doble capa aguanta, pero 'to authenticated' seria mas explicito.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- anon: sin DML en ninguna tabla. Solo REFERENCES / TRIGGER / TRUNCATE.
-- (TRUNCATE se revoca en 0007 -> S-24)
-- ---------------------------------------------------------------------------
revoke all on table public.profiles from anon;
revoke all on table public.family_members from anon;
revoke all on table public.question_requests from anon;
revoke all on table public.stories from anon;
revoke all on table public.family_invitations from anon;
revoke all on table public.family_member_deletions from anon;

grant references on table public.profiles to anon;
grant trigger on table public.profiles to anon;
grant truncate on table public.profiles to anon;

grant references on table public.family_members to anon;
grant trigger on table public.family_members to anon;
grant truncate on table public.family_members to anon;

grant references on table public.question_requests to anon;
grant trigger on table public.question_requests to anon;
grant truncate on table public.question_requests to anon;

grant references on table public.stories to anon;
grant trigger on table public.stories to anon;
grant truncate on table public.stories to anon;

-- ---------------------------------------------------------------------------
-- authenticated
--   profiles, family_members, stories -> DML completo (RLS restringe filas)
--   question_requests                 -> SOLECT (escritura solo via RPC)
--   family_invitations                -> SIN GRANTS (solo RPC)
--   family_member_deletions           -> SIN GRANTS (solo RPC)
-- (TRUNCATE se revoca en 0007 -> S-24)
-- ---------------------------------------------------------------------------
revoke all on table public.profiles from authenticated;
revoke all on table public.family_members from authenticated;
revoke all on table public.question_requests from authenticated;
revoke all on table public.stories from authenticated;
revoke all on table public.family_invitations from authenticated;
revoke all on table public.family_member_deletions from authenticated;

grant select, insert, update, delete on table public.profiles to authenticated;
grant references on table public.profiles to authenticated;
grant trigger on table public.profiles to authenticated;
grant truncate on table public.profiles to authenticated;

grant select, insert, update, delete on table public.family_members to authenticated;
grant references on table public.family_members to authenticated;
grant trigger on table public.family_members to authenticated;
grant truncate on table public.family_members to authenticated;

grant select on table public.question_requests to authenticated;
grant references on table public.question_requests to authenticated;
grant trigger on table public.question_requests to authenticated;
grant truncate on table public.question_requests to authenticated;

grant select, insert, update, delete on table public.stories to authenticated;
grant references on table public.stories to authenticated;
grant trigger on table public.stories to authenticated;
grant truncate on table public.stories to authenticated;

-- family_invitations y family_member_deletions: intencionadamente SIN grants
-- para authenticated (acceso exclusivo via SECURITY DEFINER).

-- ---------------------------------------------------------------------------
-- service_role: solo REFERENCES / TRIGGER / TRUNCATE (estado real, sin DML).
-- ---------------------------------------------------------------------------
revoke all on table public.profiles from service_role;
revoke all on table public.family_members from service_role;
revoke all on table public.question_requests from service_role;
revoke all on table public.stories from service_role;
revoke all on table public.family_invitations from service_role;
revoke all on table public.family_member_deletions from service_role;

grant references on table public.profiles to service_role;
grant trigger on table public.profiles to service_role;
grant truncate on table public.profiles to service_role;

grant references on table public.family_members to service_role;
grant trigger on table public.family_members to service_role;
grant truncate on table public.family_members to service_role;

grant references on table public.question_requests to service_role;
grant trigger on table public.question_requests to service_role;
grant truncate on table public.question_requests to service_role;

grant references on table public.stories to service_role;
grant trigger on table public.stories to service_role;
grant truncate on table public.stories to service_role;

grant references on table public.family_invitations to service_role;
grant trigger on table public.family_invitations to service_role;
grant truncate on table public.family_invitations to service_role;

grant references on table public.family_member_deletions to service_role;
grant trigger on table public.family_member_deletions to service_role;
grant truncate on table public.family_member_deletions to service_role;

-- ---------------------------------------------------------------------------
-- BUCKETS (estado real exportado de storage.buckets)
--   avatars               public=true   sin mime, sin limite  -> S-23 / S-21
--   story-audio           public=false  sin mime, sin limite  -> S-23
--   family-member-photos  public=false  5 mime, 10 MB
--   story-photos          public=false  5 mime, 10 MB
-- Los limites de story-audio y avatars se anyaden en 0007.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values
  ('avatars', 'avatars', true),
  ('story-audio', 'story-audio', false),
  ('family-member-photos', 'family-member-photos', false),
  ('story-photos', 'story-photos', false)
on conflict (id) do update set public = excluded.public;

update storage.buckets
set allowed_mime_types = '["image/jpeg","image/png","image/webp","image/heic","image/heif"]'::jsonb,
    file_size_limit = 10485760
where id in ('family-member-photos', 'story-photos');
