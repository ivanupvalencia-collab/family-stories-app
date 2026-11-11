-- =============================================================================
-- 20261111000003_baseline_functions.sql
-- Funciones exportadas de pg_proc (2026-11-11). 26 funciones en schema public.
--
-- Estado real de ACL observado:
--   * 19 funciones: EXECUTE a authenticated (ademas de postgres)
--   *  5 funciones: solo postgres (expire_family_invitations, guard_*,
--                    set_family_invitation_updated_at, protect_*)
--   *  2 funciones: ACL (default) = EXECUTE PUBLIC (handle_new_user,
--                    rls_auto_enable). Ambas son trigger/event-trigger
--                    functions: PostgreSQL impide invocarlas como funcion
--                    regular, por lo que no son explotables. Se documentan
--                    igualmente como hallazgo informativo.
--
-- SANITIZACION: el comentario original de complete_question_request contenia
-- un nombre personal real ("Iván"). Sustituido por un comentario generico.
-- Sin cambio semantico.
--
-- Todas las SECURITY DEFINER llevan SET search_path TO '' (verificado).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Invitaciones
-- ---------------------------------------------------------------------------
create or replace function public.create_family_invitation(p_family_member_id uuid)
returns table(invitation_id uuid, invitation_token text, invitation_expires_at timestamp with time zone)
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := pg_catalog.now();
  v_token text;
  v_invitation_id uuid;
  v_expires_at timestamptz;
  v_member public.family_members%rowtype;
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  select fm.*
  into v_member
  from public.family_members as fm
  where fm.id = p_family_member_id
    and fm.owner_id = v_user_id
  for update;

  if not found or v_member.linked_account_id is not null then
    raise exception using
      errcode = 'P0001',
      message = 'Family member is unavailable for invitation';
  end if;

  -- Regenerar una invitacion invalida cualquier token pendiente anterior.
  update public.family_invitations as fi
  set
    status = case
      when fi.expires_at <= v_now then 'expired'
      else 'cancelled'
    end,
    cancelled_at = case
      when fi.expires_at > v_now then v_now
      else null
    end
  where fi.family_member_id = p_family_member_id
    and fi.status = 'pending';

  -- 32 bytes = 256 bits aleatorios.
  v_token := pg_catalog.encode(
    extensions.gen_random_bytes(32),
    'hex'
  );

  v_expires_at := v_now + interval '7 days';

  insert into public.family_invitations (
    family_member_id,
    inviter_id,
    token_hash,
    status,
    created_at,
    expires_at
  )
  values (
    p_family_member_id,
    v_user_id,
    pg_catalog.encode(
      extensions.digest(v_token, 'sha256'),
      'hex'
    ),
    'pending',
    v_now,
    v_expires_at
  )
  returning id, expires_at
  into v_invitation_id, v_expires_at;

  return query
  select v_invitation_id, v_token, v_expires_at;
end;
$function$;

create or replace function public.get_family_invitation_preview(p_token text)
returns table(family_member_name text, inviter_name text, invitation_expires_at timestamp with time zone)
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_token_hash text;
  v_invitation public.family_invitations%rowtype;
begin
  if v_user_id is null then
    return;
  end if;

  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    return;
  end if;

  v_token_hash := pg_catalog.encode(
    extensions.digest(p_token, 'sha256'),
    'hex'
  );

  -- S-28: FOR UPDATE en lo que es una lectura. Serializa previews
  -- concurrentes y puede escribir (marcar expired). Se conserva fiel.
  select fi.*
  into v_invitation
  from public.family_invitations as fi
  where fi.token_hash = v_token_hash
  for update;

  if not found or v_invitation.status <> 'pending' then
    return;
  end if;

  if v_invitation.expires_at <= pg_catalog.now() then
    update public.family_invitations
    set status = 'expired'
    where id = v_invitation.id
      and status = 'pending';

    return;
  end if;

  return query
  select
    fm.name,
    p.name,
    v_invitation.expires_at
  from public.family_members as fm
  left join public.profiles as p
    on p.id = v_invitation.inviter_id
  where fm.id = v_invitation.family_member_id
    and fm.owner_id = v_invitation.inviter_id;
end;
$function$;

create or replace function public.accept_family_invitation(p_token text)
returns boolean
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_token_hash text;
  v_invitation public.family_invitations%rowtype;
  v_linked_member_id uuid;
begin
  if v_user_id is null then
    return false;
  end if;

  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  v_token_hash := pg_catalog.encode(
    extensions.digest(p_token, 'sha256'),
    'hex'
  );

  -- FOR UPDATE serializa dos intentos simultaneos con el mismo token.
  select fi.*
  into v_invitation
  from public.family_invitations as fi
  where fi.token_hash = v_token_hash
  for update;

  if not found or v_invitation.status <> 'pending' then
    return false;
  end if;

  if v_invitation.expires_at <= pg_catalog.now() then
    update public.family_invitations
    set status = 'expired'
    where id = v_invitation.id
      and status = 'pending';

    return false;
  end if;

  -- No permitimos que el invitador acepte su propia invitacion.
  if v_invitation.inviter_id = v_user_id then
    raise exception using
      errcode = 'P0001',
      message = 'cannot_accept_own_invitation';
  end if;

  -- Revalidacion defensiva:
  --   1. El familiar sigue perteneciendo al invitador.
  --   2. Todavia no esta vinculado.
  update public.family_members as fm
  set
    linked_account_id = v_user_id,
    updated_at = pg_catalog.now()
  where fm.id = v_invitation.family_member_id
    and fm.owner_id = v_invitation.inviter_id
    and fm.linked_account_id is null
  returning fm.id into v_linked_member_id;

  if not found then
    return false;
  end if;

  update public.family_invitations
  set
    status = 'accepted',
    accepted_by = v_user_id,
    accepted_at = pg_catalog.now()
  where id = v_invitation.id
    and status = 'pending';

  return true;
end;
$function$;

create or replace function public.cancel_family_invitation(p_invitation_id uuid)
returns boolean
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_invitation public.family_invitations%rowtype;
begin
  if v_user_id is null then
    return false;
  end if;

  select fi.*
  into v_invitation
  from public.family_invitations as fi
  where fi.id = p_invitation_id
    and fi.inviter_id = v_user_id
  for update;

  if not found or v_invitation.status <> 'pending' then
    return false;
  end if;

  if v_invitation.expires_at <= pg_catalog.now() then
    update public.family_invitations
    set status = 'expired'
    where id = v_invitation.id
      and status = 'pending';

    return false;
  end if;

  update public.family_invitations
  set
    status = 'cancelled',
    cancelled_at = pg_catalog.now()
  where id = v_invitation.id
    and inviter_id = v_user_id
    and status = 'pending';

  return found;
end;
$function$;

create or replace function public.expire_family_invitations()
returns integer
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_updated_count integer;
begin
  update public.family_invitations
  set status = 'expired'
  where status = 'pending'
    and expires_at <= pg_catalog.now();

  get diagnostics v_updated_count = row_count;
  return v_updated_count;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Preguntas
-- ---------------------------------------------------------------------------
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

  -- S-25 (corregido en 0007): no hay limite superior de longitud aqui.
  -- Solo permite enviar la pregunta si:
  --   1. El familiar pertenece al usuario actual.
  --   2. Ese familiar esta vinculado a una cuenta.
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

create or replace function public.complete_question_request(
  p_question_request_id uuid,
  p_audio_path text,
  p_duration_seconds integer
)
returns uuid
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_request public.question_requests%rowtype;
  v_story_id uuid;
begin
  if v_user_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'not_authenticated';
  end if;

  if p_duration_seconds is null or p_duration_seconds <= 0 then
    raise exception using
      errcode = 'P0001',
      message = 'invalid_duration';
  end if;

  if p_audio_path is null
     or trim(p_audio_path) = ''
     or p_audio_path not like p_question_request_id::text || '/%' then
    raise exception using
      errcode = 'P0001',
      message = 'invalid_audio_path';
  end if;

  -- Bloqueamos la pregunta para evitar dos respuestas simultaneas.
  select qr.*
  into v_request
  from public.question_requests qr
  where qr.id = p_question_request_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'question_request_not_found';
  end if;

  if v_request.recipient_id <> v_user_id then
    raise exception using
      errcode = 'P0001',
      message = 'not_question_recipient';
  end if;

  if v_request.status <> 'pending' then
    raise exception using
      errcode = 'P0001',
      message = 'question_already_answered';
  end if;

  -- Comprobamos que el vinculo familiar sigue siendo valido.
  if not exists (
    select 1
    from public.family_members fm
    where fm.id = v_request.family_member_id
      and fm.owner_id = v_request.sender_id
      and fm.linked_account_id = v_user_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'family_link_invalid';
  end if;

  -- Comprobamos que el archivo realmente existe en el bucket.
  if not exists (
    select 1
    from storage.objects so
    where so.bucket_id = 'story-audio'
      and so.name = p_audio_path
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'audio_not_found';
  end if;

  insert into public.stories (
    family_member_id,
    question,
    audio_path,
    duration_seconds,
    question_request_id,
    recorded_by
  )
  values (
    v_request.family_member_id,
    v_request.question_text,
    p_audio_path,
    p_duration_seconds,
    v_request.id,
    v_user_id
  )
  returning id into v_story_id;

  update public.question_requests
  set
    status = 'answered',
    answered_at = pg_catalog.now()
  where id = v_request.id;

  return v_story_id;
end;
$function$;

create or replace function public.get_my_answer_story(p_question_request_id uuid)
returns jsonb
language sql stable security definer
set search_path to ''
as $function$
  select pg_catalog.jsonb_build_object(
    'id', s.id, 'family_member_id', s.family_member_id,
    'question', qr.question_text, 'audio_path', s.audio_path,
    'duration_seconds', s.duration_seconds, 'created_at', s.created_at,
    'question_request_id', s.question_request_id,
    'recorded_by', s.recorded_by, 'photo_path', s.photo_path)
  from public.question_requests qr
  join public.stories s
    on s.question_request_id = qr.id
   and s.family_member_id = qr.family_member_id
  where qr.id = p_question_request_id
    and auth.uid() is not null
    and qr.recipient_id = auth.uid()
    and qr.status = 'answered'
    and s.recorded_by = auth.uid()
  order by s.created_at desc, s.id
  limit 1;
$function$;

create or replace function public.get_received_request_details(p_request_ids uuid[])
returns table(request_id uuid, sender_name text, duration_seconds integer)
language sql stable security definer
set search_path to ''
as $function$
  select qr.id, p.name::text, answer.duration_seconds::integer
  from public.question_requests as qr
  left join public.profiles as p on p.id = qr.sender_id
  left join lateral (
    select s.duration_seconds
    from public.stories as s
    where qr.status = 'answered'
      and s.question_request_id = qr.id
      and s.family_member_id = qr.family_member_id
      and s.recorded_by = auth.uid()
    order by s.created_at desc, s.id
    limit 1
  ) as answer on true
  where auth.uid() is not null
    and qr.recipient_id = auth.uid()
    and qr.id = any(p_request_ids)
    and pg_catalog.cardinality(p_request_ids) <= 100;
$function$;

-- ---------------------------------------------------------------------------
-- Familiares
-- ---------------------------------------------------------------------------
create or replace function public.edit_family_member_info(
  p_family_member_id uuid,
  p_name text,
  p_relationship text
)
returns jsonb
language plpgsql security definer
set search_path to ''
as $function$
declare v_member public.family_members%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_name is null or length(btrim(p_name)) = 0 or length(p_name) > 200
    or p_relationship is null or length(btrim(p_relationship)) = 0
    or length(p_relationship) > 100 then
    raise exception 'Invalid member information' using errcode = '22023';
  end if;
  update public.family_members
  set name = btrim(p_name), relationship = btrim(p_relationship)
  where id = p_family_member_id and owner_id = auth.uid()
  returning * into v_member;
  if not found then
    raise exception 'Family member unavailable' using errcode = '42501';
  end if;
  return pg_catalog.jsonb_build_object(
    'id', v_member.id, 'name', v_member.name,
    'relationship', v_member.relationship,
    'linked_account_id', v_member.linked_account_id,
    'photo_path', v_member.photo_path);
end $function$;

create or replace function public.get_visible_account_avatars(p_account_ids uuid[])
returns table(id uuid, name text, avatar_key text, avatar_url text)
language sql stable security definer
set search_path to ''
as $function$
  select p.id, p.name::text, p.avatar_key::text, p.avatar_url::text
  from public.profiles as p
  where auth.uid() is not null
    and pg_catalog.cardinality(p_account_ids) <= 100
    and p.id = any(p_account_ids)
    and (
      exists (
        select 1 from public.family_members as fm
        where fm.owner_id = auth.uid() and fm.linked_account_id = p.id
      )
      or exists (
        select 1 from public.question_requests as qr
        where qr.recipient_id = auth.uid() and qr.sender_id = p.id
          and qr.status = 'pending'
      )
    );
$function$;

-- ---------------------------------------------------------------------------
-- Fotos
-- ---------------------------------------------------------------------------
create or replace function public.set_family_member_photo(
  p_family_member_id uuid,
  p_photo_path text,
  p_expected_photo_path text
)
returns jsonb
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_member public.family_members%rowtype;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into v_member from public.family_members
  where id = p_family_member_id and owner_id = v_user
  for update;
  if not found then
    raise exception 'Family member unavailable' using errcode = '42501';
  end if;
  if v_member.photo_path is distinct from p_expected_photo_path then
    raise exception 'Photo changed; refresh and retry' using errcode = '40001';
  end if;

  if p_photo_path is not null then
    if pg_catalog.split_part(p_photo_path, '/', 1) <> v_user::text
      or pg_catalog.split_part(p_photo_path, '/', 2) <> p_family_member_id::text
      or p_photo_path !~ '^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\.(jpg|png|webp|heic|heif)$'
      or not exists (
        select 1 from storage.objects o
        where o.bucket_id = 'family-member-photos' and o.name = p_photo_path
      ) then
      raise exception 'Invalid photo reference' using errcode = '22023';
    end if;
  end if;

  update public.family_members set photo_path = p_photo_path
  where id = p_family_member_id and owner_id = v_user
  returning * into v_member;

  return pg_catalog.jsonb_build_object(
    'id', v_member.id, 'name', v_member.name,
    'relationship', v_member.relationship,
    'linked_account_id', v_member.linked_account_id,
    'photo_path', v_member.photo_path
  );
end;
$function$;

create or replace function public.set_story_photo(
  p_story_id uuid,
  p_photo_path text,
  p_expected_photo_path text
)
returns jsonb
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_story public.stories%rowtype;
  v_owner uuid;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into v_story from public.stories where id = p_story_id for update;
  if not found then
    raise exception 'Story unavailable' using errcode = '42501';
  end if;
  select owner_id into v_owner
  from public.family_members where id = v_story.family_member_id;
  if not found
     or (v_owner is distinct from v_user
         and v_story.recorded_by is distinct from v_user) then
    raise exception 'Story unavailable' using errcode = '42501';
  end if;
  if v_story.photo_path is distinct from p_expected_photo_path then
    raise exception 'Photo changed; refresh and retry' using errcode = '40001';
  end if;
  if p_photo_path is not null and (
    split_part(p_photo_path, '/', 1) <> v_user::text
    or split_part(p_photo_path, '/', 2) <> p_story_id::text
    or p_photo_path !~ '^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\.(jpg|png|webp|heic|heif)$'
    or not exists (select 1 from storage.objects o
      where o.bucket_id = 'story-photos' and o.name = p_photo_path)) then
    raise exception 'Invalid photo reference' using errcode = '22023';
  end if;
  -- Abre el trigger de la tabla solo dentro de esta transaccion.
  perform pg_catalog.set_config('app.story_photo_rpc', '1', true);
  update public.stories set photo_path = p_photo_path where id = p_story_id;
  perform pg_catalog.set_config('app.story_photo_rpc', '', true);
  return public.get_story_photo_metadata(p_story_id);
end $function$;

create or replace function public.get_story_photo_metadata(p_story_id uuid)
returns jsonb
language sql stable security definer
set search_path to ''
as $function$
  select pg_catalog.jsonb_build_object(
    'id', s.id, 'family_member_id', s.family_member_id, 'question', s.question,
    'audio_path', s.audio_path, 'duration_seconds', s.duration_seconds,
    'created_at', s.created_at, 'question_request_id', s.question_request_id,
    'recorded_by', s.recorded_by, 'photo_path', s.photo_path,
    -- S-19: can_edit se devuelve siempre true. La autorizacion real la aplica
    -- set_story_photo. Solo afecta a lo que la UI muestra.
    'can_edit', true)
  from public.stories s
  join public.family_members fm on fm.id = s.family_member_id
  where s.id = p_story_id
    and auth.uid() is not null
    and (fm.owner_id = auth.uid() or s.recorded_by = auth.uid());
$function$;

create or replace function public.story_photo_allowed(
  p_name text,
  p_operation text
)
returns boolean
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_story public.stories%rowtype;
  v_owner uuid;
begin
  if v_user is null or p_name is null or p_name !~
    '^[0-9a-f-]{36}/[0-9a-f-]{36}/[a-zA-Z0-9_-]+\.(jpg|png|webp|heic|heif)$' then
    return false;
  end if;
  -- Un UUID malformado se rechaza en vez de provocar un error de politica.
  begin
    if p_operation = 'delete' then
      -- Serializa la limpieza con el bloqueo de fila de set_story_photo.
      select * into v_story from public.stories
      where id = split_part(p_name, '/', 2)::uuid for update;
    else
      select * into v_story from public.stories
      where id = split_part(p_name, '/', 2)::uuid;
    end if;
  exception when invalid_text_representation then
    return false;
  end;
  if not found then
    return false;
  end if;
  select owner_id into v_owner
  from public.family_members where id = v_story.family_member_id;
  if v_owner is distinct from v_user
     and v_story.recorded_by is distinct from v_user then
    return false;
  end if;
  if p_operation = 'read' then
    return v_story.photo_path = p_name
      or split_part(p_name, '/', 1) = v_user::text;
  elsif p_operation = 'insert' then
    return split_part(p_name, '/', 1) = v_user::text;
  elsif p_operation = 'delete' then
    -- Nunca borra el objeto activo: primero se confirma el cambio de referencia.
    return v_story.photo_path is distinct from p_name;
  end if;
  return false;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Borrado en dos fases de un familiar
-- ---------------------------------------------------------------------------
create or replace function public.family_delete_object_allowed(
  p_bucket text,
  p_name text
)
returns boolean
language sql stable security definer
set search_path to ''
as $function$
  select auth.uid() is not null and exists (
    select 1 from public.family_member_deletions d
    join public.family_members fm on fm.id = d.family_member_id
    where d.owner_id = auth.uid()
      and fm.owner_id = auth.uid()
      and not d.completed
      and exists (select 1 from jsonb_array_elements(d.resources) r
        where r->>'bucket' = p_bucket and r->>'path' = p_name)
  );
$function$;

create or replace function public.family_delete_storage_write_allowed(
  p_bucket text,
  p_name text
)
returns boolean
language plpgsql security definer
set search_path to ''
as $function$
declare v_member uuid;
begin
  if p_bucket = 'family-member-photos' then
    select fm.id into v_member from public.family_members fm
      where fm.owner_id::text = split_part(p_name, '/', 1)
        and fm.id::text = split_part(p_name, '/', 2);
  elsif p_bucket = 'story-photos' then
    select s.family_member_id into v_member from public.stories s
      where s.id::text = split_part(p_name, '/', 2);
  elsif p_bucket = 'story-audio' then
    select qr.family_member_id into v_member from public.question_requests qr
      where qr.id::text = split_part(p_name, '/', 1);
    if v_member is null then
      select s.family_member_id into v_member from public.stories s
        where s.audio_path = p_name limit 1;
    end if;
  end if;
  -- S-18: si no resuelve el miembro, devuelve true (no-op). La politica
  -- permisiva sigue gobernando. Se conserva fiel al estado real.
  if v_member is null then return true; end if;
  perform 1 from public.family_members where id = v_member for update;
  return not exists (select 1 from public.family_member_deletions
    where family_member_id = v_member);
end $function$;

create or replace function public.prepare_family_member_delete(p_family_member_id uuid)
returns jsonb
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_owner uuid;
  v_plan public.family_member_deletions%rowtype;
  v_resources jsonb;
  v_stories jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select owner_id into v_owner from public.family_members
  where id = p_family_member_id for update;
  if not found then
    select * into v_plan from public.family_member_deletions
    where family_member_id = p_family_member_id
      and owner_id = auth.uid() and completed;
    if not found then
      raise exception 'Family member unavailable' using errcode = '42501';
    end if;
    return jsonb_build_object(
      'resources', v_plan.resources, 'story_ids', v_plan.story_ids);
  end if;
  if v_owner is distinct from auth.uid() then
    raise exception 'Only the family owner may delete' using errcode = '42501';
  end if;
  select * into v_plan from public.family_member_deletions
  where family_member_id = p_family_member_id;
  if found then
    if v_plan.owner_id is distinct from auth.uid() or v_plan.completed then
      raise exception 'Owner deletion plan required' using errcode = '42501';
    end if;
    return jsonb_build_object(
      'resources', v_plan.resources, 'story_ids', v_plan.story_ids);
  end if;
  perform id from public.stories
  where family_member_id = p_family_member_id for update;
  perform id from public.question_requests
  where family_member_id = p_family_member_id for update;

  -- Rechaza referencias de audio ambiguas en lugar de borrar el objeto de
  -- otra familia.
  if exists (
    select 1 from public.stories s
    join public.stories other on other.audio_path = s.audio_path
      and other.family_member_id <> s.family_member_id
    where s.family_member_id = p_family_member_id
      and s.audio_path is not null) then
    raise exception 'Audio is shared with another family member; manual review required'
      using errcode = '55000';
  end if;

  select coalesce(jsonb_agg(id::text), '[]'::jsonb) into v_stories
  from public.stories where family_member_id = p_family_member_id;

  -- Referencias reales mas objetos existentes en los espacios verificados.
  with targets(bucket, path) as (
    select 'family-member-photos', photo_path from public.family_members
      where id = p_family_member_id
    union select 'story-photos', photo_path from public.stories
      where family_member_id = p_family_member_id
    union select 'story-audio', audio_path from public.stories
      where family_member_id = p_family_member_id
    union select o.bucket_id, o.name from storage.objects o where
      (o.bucket_id = 'family-member-photos'
        and split_part(o.name, '/', 1) = v_owner::text
        and split_part(o.name, '/', 2) = p_family_member_id::text)
      or (o.bucket_id = 'story-photos'
        and exists (select 1 from public.stories s
          where s.family_member_id = p_family_member_id
            and s.id::text = split_part(o.name, '/', 2)))
      or (o.bucket_id = 'story-audio'
        and exists (select 1 from public.question_requests qr
          where qr.family_member_id = p_family_member_id
            and qr.id::text = split_part(o.name, '/', 1)))
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('bucket', bucket, 'path', path)
      order by bucket, path), '[]'::jsonb)
  into v_resources
  from targets where path is not null and path <> '';

  if exists (
    select 1 from jsonb_array_elements(v_resources) r
    join public.stories s on r->>'bucket' = 'story-audio'
      and r->>'path' = s.audio_path
    where s.family_member_id <> p_family_member_id) then
    raise exception 'Audio namespace is shared; manual review required'
      using errcode = '55000';
  end if;

  -- Desacopla las referencias de foto ANTES de permitir el borrado.
  perform pg_catalog.set_config('app.story_photo_rpc', '1', true);
  update public.stories set photo_path = null
  where family_member_id = p_family_member_id and photo_path is not null;
  perform pg_catalog.set_config('app.story_photo_rpc', '', true);
  update public.family_members set photo_path = null
  where id = p_family_member_id and photo_path is not null;

  insert into public.family_member_deletions(family_member_id, owner_id, resources, story_ids)
  values(p_family_member_id, v_owner, v_resources, v_stories);

  return jsonb_build_object('resources', v_resources, 'story_ids', v_stories);
end $function$;

create or replace function public.finish_family_member_delete(p_family_member_id uuid)
returns void
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_owner uuid;
  v_plan public.family_member_deletions%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select owner_id into v_owner from public.family_members
  where id = p_family_member_id for update;
  select * into v_plan from public.family_member_deletions
  where family_member_id = p_family_member_id and owner_id = auth.uid()
  for update;
  if not found then
    raise exception 'Owner deletion plan required' using errcode = '42501';
  end if;
  if v_plan.completed then return; end if;
  if v_owner is distinct from auth.uid() then
    raise exception 'Only the family owner may delete' using errcode = '42501';
  end if;
  -- El cliente no puede poner este flag ni hacer DELETE directo tras preparar.
  -- El flag y el CASCADE estan en una transaccion; un fallo de trigger lo
  -- revierte.
  update public.family_member_deletions
  set completed = true where family_member_id = p_family_member_id;
  -- El trigger padre verifica de forma independiente que no queden filas de
  -- metadata en Storage.
  delete from public.family_members
  where id = p_family_member_id and owner_id = auth.uid();
end $function$;

-- ---------------------------------------------------------------------------
-- Trigger functions (no invocables como funcion regular)
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path to ''
as $function$
begin
  insert into public.profiles (id, name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      'Usuario'
    )
  );
  return new;
end;
$function$;

create or replace function public.set_family_invitation_updated_at()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

create or replace function public.protect_family_member_linked_account()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if current_user in ('anon', 'authenticated', 'authenticator') then
    if tg_op = 'INSERT' and new.linked_account_id is not null then
      raise exception using
        errcode = '42501',
        message = 'linked_account_id can only be assigned through the invitation flow';
    end if;
    if tg_op = 'UPDATE'
       and new.linked_account_id is distinct from old.linked_account_id then
      raise exception using
        errcode = '42501',
        message = 'linked_account_id can only be changed through the invitation flow';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.guard_story_photo_path_change()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if tg_op = 'INSERT' then
    if new.photo_path is not null
      and coalesce(pg_catalog.current_setting('app.story_photo_rpc', true), '') <> '1' then
      raise exception 'photo_path must be managed through set_story_photo'
        using errcode = '42501';
    end if;
  elsif new.photo_path is distinct from old.photo_path
    and coalesce(pg_catalog.current_setting('app.story_photo_rpc', true), '') <> '1' then
    raise exception 'photo_path must be managed through set_story_photo'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

create or replace function public.guard_family_delete_parent()
returns trigger
language plpgsql security definer
set search_path to ''
as $function$
declare v_resources jsonb;
begin
  if tg_op = 'INSERT' then
    if exists (select 1 from public.family_member_deletions
        where family_member_id = new.id) then
      raise exception 'Deleted family ID cannot be reused' using errcode = '55000';
    end if;
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if exists (select 1 from public.family_member_deletions
        where family_member_id = old.id) then
      raise exception 'Family member deletion is in progress' using errcode = '55000';
    end if;
    return new;
  end if;
  if old.owner_id is distinct from auth.uid() then
    raise exception 'Only the family owner may delete' using errcode = '42501';
  end if;
  select resources into v_resources from public.family_member_deletions
  where family_member_id = old.id and owner_id = auth.uid() and completed;
  if not found then
    raise exception 'Prepare deletion first' using errcode = '55000';
  end if;
  if exists (
    select 1 from storage.objects o
    join jsonb_array_elements(v_resources) r
      on o.bucket_id = r->>'bucket' and o.name = r->>'path') then
    raise exception 'Storage cleanup is incomplete' using errcode = '55000';
  end if;
  return old;
end $function$;

create or replace function public.guard_family_delete_child()
returns trigger
language plpgsql security definer
set search_path to ''
as $function$
declare
  v_member uuid;
  v_new_member uuid;
begin
  if tg_op <> 'INSERT' then
    v_member := (to_jsonb(old)->>tg_argv[0])::uuid;
  end if;
  if tg_op <> 'DELETE' then
    v_new_member := (to_jsonb(new)->>tg_argv[0])::uuid;
  end if;
  -- Bloquea ambos padres para mover; cambiar una FK provista por el cliente
  -- no puede eludir la congelacion de la familia antigua. Durante el CASCADE
  -- el padre ya no existe.
  perform id from public.family_members
  where id in (v_member, v_new_member) order by id for update;
  if exists (
    select 1 from public.family_member_deletions d
    join public.family_members fm on fm.id = d.family_member_id
    where d.family_member_id in (v_member, v_new_member)) then
    raise exception 'Family member deletion is in progress' using errcode = '55000';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $function$;

-- Event trigger: activa RLS automaticamente en cualquier tabla nueva de public.
create or replace function public.rls_auto_enable()
returns event_trigger
language plpgsql security definer
set search_path to 'pg_catalog'
as $function$
declare
  cmd record;
begin
  for cmd in
    select * from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      and object_type in ('table', 'partitioned table')
  loop
    if cmd.schema_name is not null
       and cmd.schema_name in ('public') then
      begin
        execute format('alter table if exists %s enable row level security',
          cmd.object_identity);
        raise log 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      exception
        when others then
          raise log 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      end;
    end if;
  end loop;
end;
$function$;

-- ---------------------------------------------------------------------------
-- GRANTS: replican el ACL observado en pg_proc.
-- ---------------------------------------------------------------------------
revoke all on function public.create_family_invitation(uuid) from public, anon;
revoke all on function public.get_family_invitation_preview(text) from public, anon;
revoke all on function public.accept_family_invitation(text) from public, anon;
revoke all on function public.cancel_family_invitation(uuid) from public, anon;
revoke all on function public.expire_family_invitations() from public, anon, authenticated;
revoke all on function public.send_question_request(uuid, text) from public, anon;
revoke all on function public.complete_question_request(uuid, text, integer) from public, anon;
revoke all on function public.get_my_answer_story(uuid) from public, anon;
revoke all on function public.get_received_request_details(uuid[]) from public, anon;
revoke all on function public.edit_family_member_info(uuid, text, text) from public, anon;
revoke all on function public.get_visible_account_avatars(uuid[]) from public, anon;
revoke all on function public.set_family_member_photo(uuid, text, text) from public, anon;
revoke all on function public.set_story_photo(uuid, text, text) from public, anon;
revoke all on function public.get_story_photo_metadata(uuid) from public, anon;
revoke all on function public.story_photo_allowed(text, text) from public, anon;
revoke all on function public.family_delete_object_allowed(text, text) from public, anon;
revoke all on function public.family_delete_storage_write_allowed(text, text) from public, anon;
revoke all on function public.prepare_family_member_delete(uuid) from public, anon;
revoke all on function public.finish_family_member_delete(uuid) from public, anon;
-- Trigger/event functions: ACL era (default) = PUBLIC. Se estrecha a postgres.
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.set_family_invitation_updated_at() from public, anon, authenticated;
revoke all on function public.protect_family_member_linked_account() from public, anon, authenticated;
revoke all on function public.guard_story_photo_path_change() from public, anon, authenticated;
revoke all on function public.guard_family_delete_parent() from public, anon, authenticated;
revoke all on function public.guard_family_delete_child() from public, anon, authenticated;
revoke all on function public.rls_auto_enable() from public, anon, authenticated;

grant execute on function public.create_family_invitation(uuid) to authenticated;
grant execute on function public.get_family_invitation_preview(text) to authenticated;
grant execute on function public.accept_family_invitation(text) to authenticated;
grant execute on function public.cancel_family_invitation(uuid) to authenticated;
grant execute on function public.send_question_request(uuid, text) to authenticated;
grant execute on function public.complete_question_request(uuid, text, integer) to authenticated;
grant execute on function public.get_my_answer_story(uuid) to authenticated;
grant execute on function public.get_received_request_details(uuid[]) to authenticated;
grant execute on function public.edit_family_member_info(uuid, text, text) to authenticated;
grant execute on function public.get_visible_account_avatars(uuid[]) to authenticated;
grant execute on function public.set_family_member_photo(uuid, text, text) to authenticated;
grant execute on function public.set_story_photo(uuid, text, text) to authenticated;
grant execute on function public.get_story_photo_metadata(uuid) to authenticated;
grant execute on function public.story_photo_allowed(text, text) to authenticated;
grant execute on function public.family_delete_object_allowed(text, text) to authenticated;
grant execute on function public.family_delete_storage_write_allowed(text, text) to authenticated;
grant execute on function public.prepare_family_member_delete(uuid) to authenticated;
grant execute on function public.finish_family_member_delete(uuid) to authenticated;
