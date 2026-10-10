-- MANUAL ONLY. Run before 02_family_member_photo_rpc.sql.
begin;

alter table public.family_members add column if not exists photo_path text;

-- NULL keeps every existing member compatible. References belong only to the
-- owner/member namespace, independently of linked_account_id.
do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname = 'family_members_photo_path_namespace'
      and conrelid = 'public.family_members'::regclass
  ) then
    alter table public.family_members
      add constraint family_members_photo_path_namespace check (
        photo_path is null or (
          split_part(photo_path, '/', 1) = owner_id::text
          and split_part(photo_path, '/', 2) = id::text
          and photo_path ~ '^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+\.(jpg|png|webp|heic|heif)$'
        )
      );
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('family-member-photos', 'family-member-photos', false, 10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do update set public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- New bucket only: existing avatar/audio policies remain unchanged.
-- Always reference storage.objects.name, never the family member's name.
drop policy if exists "Owners read family member photos" on storage.objects;
create policy "Owners read family member photos" on storage.objects
for select to authenticated using (
  bucket_id = 'family-member-photos'
  and (storage.foldername(storage.objects.name))[1] = (select auth.uid())::text
  and exists (select 1 from public.family_members fm
    where fm.id::text = (storage.foldername(storage.objects.name))[2]
      and fm.owner_id = (select auth.uid()))
);

drop policy if exists "Owners upload family member photos" on storage.objects;
create policy "Owners upload family member photos" on storage.objects
for insert to authenticated with check (
  bucket_id = 'family-member-photos'
  and (storage.foldername(storage.objects.name))[1] = (select auth.uid())::text
  and exists (select 1 from public.family_members fm
    where fm.id::text = (storage.foldername(storage.objects.name))[2]
      and fm.owner_id = (select auth.uid()))
);

drop policy if exists "Owners replace family member photos" on storage.objects;
create policy "Owners replace family member photos" on storage.objects
for update to authenticated using (
  bucket_id = 'family-member-photos'
  and (storage.foldername(storage.objects.name))[1] = (select auth.uid())::text
  and exists (select 1 from public.family_members fm
    where fm.id::text = (storage.foldername(storage.objects.name))[2]
      and fm.owner_id = (select auth.uid()))
) with check (
  bucket_id = 'family-member-photos'
  and (storage.foldername(storage.objects.name))[1] = (select auth.uid())::text
  and exists (select 1 from public.family_members fm
    where fm.id::text = (storage.foldername(storage.objects.name))[2]
      and fm.owner_id = (select auth.uid()))
);

drop policy if exists "Owners delete family member photos" on storage.objects;
create policy "Owners delete family member photos" on storage.objects
for delete to authenticated using (
  bucket_id = 'family-member-photos'
  and (storage.foldername(storage.objects.name))[1] = (select auth.uid())::text
  and exists (select 1 from public.family_members fm
    where fm.id::text = (storage.foldername(storage.objects.name))[2]
      and fm.owner_id = (select auth.uid()))
);

-- Restrictive guards keep this bucket owner-only even if the project has an
-- older permissive Storage policy covering all buckets. Other buckets pass.
drop policy if exists "Family photos require their owner" on storage.objects;
create policy "Family photos require their owner" on storage.objects
as restrictive for all to authenticated using (
  bucket_id <> 'family-member-photos' or (
    (storage.foldername(storage.objects.name))[1] = (select auth.uid())::text
    and exists (select 1 from public.family_members fm
      where fm.id::text = (storage.foldername(storage.objects.name))[2]
        and fm.owner_id = (select auth.uid()))
  )
) with check (
  bucket_id <> 'family-member-photos' or (
    (storage.foldername(storage.objects.name))[1] = (select auth.uid())::text
    and exists (select 1 from public.family_members fm
      where fm.id::text = (storage.foldername(storage.objects.name))[2]
        and fm.owner_id = (select auth.uid()))
  )
);

drop policy if exists "Family photos deny anonymous access" on storage.objects;
create policy "Family photos deny anonymous access" on storage.objects
as restrictive for all to anon
using (bucket_id <> 'family-member-photos')
with check (bucket_id <> 'family-member-photos');

notify pgrst, 'reload schema';
commit;
