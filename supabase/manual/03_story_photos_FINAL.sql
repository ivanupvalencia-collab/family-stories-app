-- MANUAL ONLY. Execute before 04_story_photo_rpc.sql. No existing RLS is widened.
begin;
alter table public.stories add column if not exists photo_path text;
do $$ begin
  if not exists (select 1 from pg_catalog.pg_constraint
    where conname = 'stories_photo_namespace' and conrelid = 'public.stories'::regclass) then
    alter table public.stories add constraint stories_photo_namespace check (
      photo_path is null or (split_part(photo_path, '/', 2) = id::text and
        photo_path ~ '^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\.(jpg|png|webp|heic|heif)$'));
  end if;
end $$;
-- Prevent clients from bypassing set_story_photo by updating photo_path directly.
-- The RPC in 04_story_photo_rpc.sql opens this guard only for its own transaction.
create or replace function public.guard_story_photo_path_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.photo_path is not null
      and pg_catalog.coalesce(pg_catalog.current_setting('app.story_photo_rpc', true), '') <> '1' then
      raise exception 'photo_path must be managed through set_story_photo' using errcode = '42501';
    end if;
  elsif new.photo_path is distinct from old.photo_path
    and pg_catalog.coalesce(pg_catalog.current_setting('app.story_photo_rpc', true), '') <> '1' then
    raise exception 'photo_path must be managed through set_story_photo' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.guard_story_photo_path_change() from public, anon, authenticated;

drop trigger if exists guard_story_photo_path_change on public.stories;
create trigger guard_story_photo_path_change
before insert or update of photo_path on public.stories
for each row execute function public.guard_story_photo_path_change();

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('story-photos', 'story-photos', false, 10485760,
  array['image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict(id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Table RLS deliberately remains owner-oriented. The helper checks the actual
-- story relationship with elevated SELECT; it never trusts only a folder ID.
create or replace function public.story_photo_allowed(p_name text, p_operation text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_story public.stories%rowtype; v_owner uuid;
begin
  if v_user is null or p_name is null or p_name !~
    '^[0-9a-f-]{36}/[0-9a-f-]{36}/[a-zA-Z0-9_-]+\.(jpg|png|webp|heic|heif)$' then return false; end if;
  -- A malformed UUID is rejected instead of causing a policy evaluation error.
  begin
    if p_operation = 'delete' then
      -- Serialize cleanup with set_story_photo's story-row lock. A staged
      -- object cannot be deleted concurrently while it becomes the reference.
      select * into v_story from public.stories
        where id = split_part(p_name, '/', 2)::uuid for update;
    else
      select * into v_story from public.stories where id = split_part(p_name, '/', 2)::uuid;
    end if;
  exception when invalid_text_representation then return false; end;
  if not found then return false; end if;
  select owner_id into v_owner from public.family_members where id = v_story.family_member_id;
  if v_owner is distinct from v_user and v_story.recorded_by is distinct from v_user then return false; end if;
  if p_operation = 'read' then
    return v_story.photo_path = p_name or split_part(p_name, '/', 1) = v_user::text;
  elsif p_operation = 'insert' then
    return split_part(p_name, '/', 1) = v_user::text;
  elsif p_operation = 'delete' then
    -- Never delete the active object: commit the reference change first.
    return v_story.photo_path is distinct from p_name;
  end if;
  return false;
end $$;
revoke all on function public.story_photo_allowed(text,text) from public, anon;
grant execute on function public.story_photo_allowed(text,text) to authenticated;

drop policy if exists "Participants read story photos" on storage.objects;
create policy "Participants read story photos" on storage.objects for select to authenticated
using (bucket_id = 'story-photos' and public.story_photo_allowed(storage.objects.name,'read'));
drop policy if exists "Participants upload story photos" on storage.objects;
create policy "Participants upload story photos" on storage.objects for insert to authenticated
with check (bucket_id = 'story-photos' and public.story_photo_allowed(storage.objects.name,'insert'));
drop policy if exists "Participants clean inactive story photos" on storage.objects;
create policy "Participants clean inactive story photos" on storage.objects for delete to authenticated
using (bucket_id = 'story-photos' and public.story_photo_allowed(storage.objects.name,'delete'));

-- Restrictive bucket-specific guards also protect against older permissive
-- policies covering every bucket. Unique uploads need no object UPDATE.
drop policy if exists "Story photo read guard" on storage.objects;
create policy "Story photo read guard" on storage.objects as restrictive for select to authenticated
using (bucket_id <> 'story-photos' or public.story_photo_allowed(storage.objects.name,'read'));
drop policy if exists "Story photo insert guard" on storage.objects;
create policy "Story photo insert guard" on storage.objects as restrictive for insert to authenticated
with check (bucket_id <> 'story-photos' or public.story_photo_allowed(storage.objects.name,'insert'));
drop policy if exists "Story photo delete guard" on storage.objects;
create policy "Story photo delete guard" on storage.objects as restrictive for delete to authenticated
using (bucket_id <> 'story-photos' or public.story_photo_allowed(storage.objects.name,'delete'));
drop policy if exists "Story photo update guard" on storage.objects;
create policy "Story photo update guard" on storage.objects as restrictive for update to authenticated
using (bucket_id <> 'story-photos') with check (bucket_id <> 'story-photos');
drop policy if exists "Story photos deny anonymous" on storage.objects;
create policy "Story photos deny anonymous" on storage.objects as restrictive for all to anon
using (bucket_id <> 'story-photos') with check (bucket_id <> 'story-photos');
notify pgrst, 'reload schema';
commit;
