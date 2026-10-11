-- MANUAL ONLY. Run after the existing schema; no RLS/Storage changes.
-- avatars is already public; this script only grants authorized metadata access.
begin;

create or replace function public.get_visible_account_avatars(p_account_ids uuid[])
returns table (id uuid, name text, avatar_key text, avatar_url text)
language sql stable security definer
set search_path = ''
as $$
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
$$;

revoke all on function public.get_visible_account_avatars(uuid[]) from public, anon;
grant execute on function public.get_visible_account_avatars(uuid[]) to authenticated;

commit;
