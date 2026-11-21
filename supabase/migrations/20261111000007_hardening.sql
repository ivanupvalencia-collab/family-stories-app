-- =============================================================================
-- 20261111000007_hardening.sql
-- CORRECCIONES REALES sobre el baseline. Este archivo SI cambia el estado
-- respecto a produccion. Revisar antes de aplicar.
--
--   S-23  Bucket story-audio sin allowed_mime_types ni file_size_limit.
--         Bucket avatars igual, y ademas es publico.
--   S-24  anon / authenticated / service_role con TRUNCATE sobre 4 tablas.
--         TRUNCATE no esta cubierto por RLS.
--   S-25  send_question_request sin limite superior de longitud en
--         question_text. El CHECK existente solo exige > 0.
--   S-31  story-audio sin politica restrictive deny-anon (los demas buckets
--         privados si la tienen). Hoy anon no ve nada porque todas sus
--         politicas permisivas son 'to authenticated'; se anade la capa
--         explicita por consistencia y defensa en profundidad.
--
-- NOTA: 0003 versiona send_question_request con el cuerpo original. Al
-- aplicar 0007 se vuelve a crear con el limite; el orden 0003 -> 0007 deja la
-- version final correcta.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- S-23: limites de bucket
-- ---------------------------------------------------------------------------
-- story-audio: audio comprimido. 20 MB es holgura frente a los ~10 MB que
-- genera la app por grabacion, y evita subidas arbitrarias.
update storage.buckets
set allowed_mime_types = '["audio/mp4","audio/m4a","audio/aac","audio/mpeg","audio/wav","audio/x-wav"]'::jsonb,
    file_size_limit = 20971520
where id = 'story-audio';

-- avatars: bucket PUBLICO sin ninguna restriccion. Se limita a imagenes de
-- razonable tamano. El MIME declarado por el cliente no es fiable por si solo
-- (S-12); el tamano y el tipo ya reducen sustancialmente el abuso.
update storage.buckets
set allowed_mime_types = '["image/jpeg","image/png","image/webp","image/heic","image/heif"]'::jsonb,
    file_size_limit = 5242880
where id = 'avatars';

-- ---------------------------------------------------------------------------
-- S-24: revocar TRUNCATE (no cubierto por RLS)
-- ---------------------------------------------------------------------------
revoke truncate on table public.profiles from anon, authenticated, service_role;
revoke truncate on table public.family_members from anon, authenticated, service_role;
revoke truncate on table public.question_requests from anon, authenticated, service_role;
revoke truncate on table public.stories from anon, authenticated, service_role;
revoke truncate on table public.family_invitations from anon, authenticated, service_role;
revoke truncate on table public.family_member_deletions from anon, authenticated, service_role;

-- REFERENCES / TRIGGER se mantienen: son el comportamiento por defecto de
-- Supabase y no permiten leer ni modificar filas.

-- ---------------------------------------------------------------------------
-- S-31: deny-anon explicito para story-audio (consistencia con los demas
-- buckets privados)
-- ---------------------------------------------------------------------------
drop policy if exists "Story audio deny anonymous" on storage.objects;
create policy "Story audio deny anonymous"
  on storage.objects as restrictive for all
  to anon
  using (bucket_id <> 'story-audio'::text)
  with check (bucket_id <> 'story-audio'::text);

-- ---------------------------------------------------------------------------
-- S-25: limite superior de question_text
--   500 caracteres: la UI de la app es un campo de pregunta corta; 500 deja
--   margen amplio y bloquea subidas de texto arbitrario.
--
--   Se anyade como NOT VALID para no romper con filas existentes que pudieran
--   superar el limite, y luego se valida: si VALIDATE falla por datos
--   historicos, el constraint sigue protegiendo escrituras nuevas.
-- ---------------------------------------------------------------------------
alter table public.question_requests
  drop constraint if exists question_text_max_length;
alter table public.question_requests
  add constraint question_text_max_length
  check (char_length(question_text) <= 500) not valid;

do $$
begin
  alter table public.question_requests
    validate constraint question_text_max_length;
exception
  when check_violation then
    raise notice 'question_text_max_length: filas historicas superan 500 chars; constraint queda NOT VALID pero protege escrituras nuevas';
end $$;

-- Mismo limite en la RPC, para que el error sea temprano y tipado en vez de
-- un check_violation generico.
create or replace function public.send_question_request(
  p_family_member_id uuid,
  p_question_text text
)
returns uuid
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_recipient_id uuid;
  v_request_id uuid;
  v_question_text text;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  v_question_text := trim(p_question_text);

  if v_question_text is null or v_question_text = '' then
    raise exception 'invalid_question';
  end if;

  -- S-25: limite superior (el baseline solo exigia no-vacio).
  if char_length(v_question_text) > 500 then
    raise exception 'question_too_long' using errcode = '22023';
  end if;

  select fm.linked_account_id
  into v_recipient_id
  from public.family_members as fm
  where fm.id = p_family_member_id
    and fm.owner_id = v_user_id
    and fm.linked_account_id is not null;

  if not found then
    raise exception 'family_member_not_linked';
  end if;

  if v_recipient_id = v_user_id then
    raise exception 'cannot_send_to_self';
  end if;

  insert into public.question_requests (
    sender_id,
    recipient_id,
    family_member_id,
    question_text
  )
  values (
    v_user_id,
    v_recipient_id,
    p_family_member_id,
    v_question_text
  )
  returning id into v_request_id;

  return v_request_id;
end;
$function$;

revoke all on function public.send_question_request(uuid, text) from public, anon;
grant execute on function public.send_question_request(uuid, text) to authenticated;
