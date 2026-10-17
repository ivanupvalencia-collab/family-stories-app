-- MANUAL ONLY. Apply after the installed 03/04 FINAL scripts.
-- complete_question_request is not defined in this repository. The known
-- failure is in the stories INSERT/UPDATE trigger installed by 03 FINAL.
-- COALESCE is SQL syntax, not a function in the pg_catalog schema.
-- Replace only the two invalid qualifications; keep the photo guard intact.
-- The RPC (including SECURITY DEFINER, search_path and ACL) is NOT modified.
-- CREATE OR REPLACE preserves the existing trigger function's owner and ACL.
-- Its invoker security mode and empty search_path match 03 FINAL exactly.
-- No policy, Storage object, table row, grant or trigger binding is changed.
begin;

-- Fail rather than create a new function with default EXECUTE permissions
-- if the prerequisite photo guard is missing from the installed schema.
do $$ begin
  if pg_catalog.to_regprocedure('public.guard_story_photo_path_change()') is null then
    raise exception 'Install/review 03_story_photos_FINAL.sql before applying 09';
  end if;
end $$;

create or replace function public.guard_story_photo_path_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.photo_path is not null
      and COALESCE(pg_catalog.current_setting('app.story_photo_rpc', true), '') <> '1' then
      raise exception 'photo_path must be managed through set_story_photo' using errcode = '42501';
    end if;
  elsif new.photo_path is distinct from old.photo_path
    and COALESCE(pg_catalog.current_setting('app.story_photo_rpc', true), '') <> '1' then
    raise exception 'photo_path must be managed through set_story_photo' using errcode = '42501';
  end if;
  return new;
end $$;

commit;
