-- MANUAL ONLY: install in the Supabase SQL editor before testing playback
-- from "Tus respuestas". This file is not applied by the Flutter app.
begin;

create or replace function public.get_my_answer_story(p_question_request_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'id', s.id,
    'family_member_id', s.family_member_id,
    'question', qr.question_text,
    'audio_path', s.audio_path,
    'duration_seconds', s.duration_seconds,
    'created_at', s.created_at,
    'question_request_id', s.question_request_id,
    'recorded_by', s.recorded_by
  )
  from public.question_requests as qr
  join public.stories as s
    on s.question_request_id = qr.id
    and s.family_member_id = qr.family_member_id
  where qr.id = p_question_request_id
    and auth.uid() is not null
    and qr.recipient_id = auth.uid()
    and qr.status = 'answered'
    and s.recorded_by = auth.uid()
  order by s.created_at desc, s.id
  limit 1;
$$;

revoke all on function public.get_my_answer_story(uuid) from public, anon;
grant execute on function public.get_my_answer_story(uuid) to authenticated;

commit;
