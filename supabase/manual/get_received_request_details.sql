-- MANUAL ONLY. Optional Home enrichment; no existing policy is changed.
begin;

create or replace function public.get_received_request_details(p_request_ids uuid[])
returns table (request_id uuid, sender_name text, duration_seconds integer)
language sql stable security definer
set search_path = ''
as $$
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
$$;

revoke all on function public.get_received_request_details(uuid[]) from public, anon;
grant execute on function public.get_received_request_details(uuid[]) to authenticated;

commit;
