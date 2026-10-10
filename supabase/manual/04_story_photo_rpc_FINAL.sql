-- MANUAL ONLY. Requires 03_story_photos.sql. Does not alter complete_question_request.
begin;
create or replace function public.get_story_photo_metadata(p_story_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select pg_catalog.jsonb_build_object(
    'id', s.id, 'family_member_id', s.family_member_id, 'question', s.question,
    'audio_path', s.audio_path, 'duration_seconds', s.duration_seconds,
    'created_at', s.created_at, 'question_request_id', s.question_request_id,
    'recorded_by', s.recorded_by, 'photo_path', s.photo_path, 'can_edit', true)
  from public.stories s join public.family_members fm on fm.id = s.family_member_id
  where s.id = p_story_id and auth.uid() is not null
    and (fm.owner_id = auth.uid() or s.recorded_by = auth.uid());
$$;
revoke all on function public.get_story_photo_metadata(uuid) from public, anon;
grant execute on function public.get_story_photo_metadata(uuid) to authenticated;

create or replace function public.set_story_photo(p_story_id uuid, p_photo_path text, p_expected_photo_path text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_story public.stories%rowtype; v_owner uuid;
begin
  if v_user is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select * into v_story from public.stories where id = p_story_id for update;
  if not found then raise exception 'Story unavailable' using errcode = '42501'; end if;
  select owner_id into v_owner from public.family_members where id = v_story.family_member_id;
  if not found or (v_owner is distinct from v_user and v_story.recorded_by is distinct from v_user) then
    raise exception 'Story unavailable' using errcode = '42501'; end if;
  if v_story.photo_path is distinct from p_expected_photo_path then
    raise exception 'Photo changed; refresh and retry' using errcode = '40001'; end if;
  if p_photo_path is not null and (
    split_part(p_photo_path,'/',1) <> v_user::text or split_part(p_photo_path,'/',2) <> p_story_id::text
    or p_photo_path !~ '^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\.(jpg|png|webp|heic|heif)$'
    or not exists (select 1 from storage.objects o where o.bucket_id = 'story-photos' and o.name = p_photo_path)) then
    raise exception 'Invalid photo reference' using errcode = '22023'; end if;
  -- Open the table trigger only inside this transaction, then update the reference.
  perform pg_catalog.set_config('app.story_photo_rpc', '1', true);
  update public.stories set photo_path = p_photo_path where id = p_story_id;
  perform pg_catalog.set_config('app.story_photo_rpc', '', true);
  return public.get_story_photo_metadata(p_story_id);
end $$;
revoke all on function public.set_story_photo(uuid,text,text) from public, anon;
grant execute on function public.set_story_photo(uuid,text,text) to authenticated;

-- Keep the existing recipient-only contract; only add the nullable photo field.
create or replace function public.get_my_answer_story(p_question_request_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select pg_catalog.jsonb_build_object('id',s.id,'family_member_id',s.family_member_id,
    'question',qr.question_text,'audio_path',s.audio_path,'duration_seconds',s.duration_seconds,
    'created_at',s.created_at,'question_request_id',s.question_request_id,
    'recorded_by',s.recorded_by,'photo_path',s.photo_path)
  from public.question_requests qr join public.stories s
    on s.question_request_id = qr.id and s.family_member_id = qr.family_member_id
  where qr.id = p_question_request_id and auth.uid() is not null
    and qr.recipient_id = auth.uid() and qr.status = 'answered' and s.recorded_by = auth.uid()
  order by s.created_at desc, s.id limit 1;
$$;
revoke all on function public.get_my_answer_story(uuid) from public, anon;
grant execute on function public.get_my_answer_story(uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
