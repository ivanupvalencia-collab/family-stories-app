-- MANUAL ONLY. Narrow name/relationship editor, independently of linking/photos.
begin;
create or replace function public.edit_family_member_info(p_family_member_id uuid, p_name text, p_relationship text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_member public.family_members%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_name is null or length(btrim(p_name)) = 0 or length(p_name) > 200
    or p_relationship is null or length(btrim(p_relationship)) = 0 or length(p_relationship) > 100 then
    raise exception 'Invalid member information' using errcode = '22023'; end if;
  update public.family_members set name = btrim(p_name), relationship = btrim(p_relationship)
  where id = p_family_member_id and owner_id = auth.uid() returning * into v_member;
  if not found then raise exception 'Family member unavailable' using errcode = '42501'; end if;
  return pg_catalog.jsonb_build_object('id',v_member.id,'name',v_member.name,'relationship',v_member.relationship,
    'linked_account_id',v_member.linked_account_id,'photo_path',v_member.photo_path);
end $$;
revoke all on function public.edit_family_member_info(uuid,text,text) from public, anon;
grant execute on function public.edit_family_member_info(uuid,text,text) to authenticated;
notify pgrst, 'reload schema';
commit;
