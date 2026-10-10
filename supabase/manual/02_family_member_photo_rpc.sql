-- MANUAL ONLY. Requires 01_family_member_photos.sql.
-- Update only photo_path without granting broader UPDATE access to the table.
begin;

create or replace function public.set_family_member_photo(
  p_family_member_id uuid,
  p_photo_path text,
  p_expected_photo_path text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

revoke all on function public.set_family_member_photo(uuid, text, text) from public, anon;
grant execute on function public.set_family_member_photo(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
commit;
