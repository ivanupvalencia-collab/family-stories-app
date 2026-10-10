-- READ ONLY / MANUAL. The baseline schema is not versioned in this repository.
-- Do NOT enable remote deletion until these dependencies and Storage cleanup
-- have been reviewed. Do not delete storage.objects with SQL (it leaves blobs).
select c.conrelid::regclass as referencing_table, c.confrelid::regclass as referenced_table,
  c.conname, pg_catalog.pg_get_constraintdef(c.oid) as definition
from pg_catalog.pg_constraint c
where c.contype = 'f' and (c.confrelid in (
  'public.family_members'::regclass, 'public.stories'::regclass, 'public.question_requests'::regclass)
  or c.conrelid in ('public.family_members'::regclass, 'public.stories'::regclass, 'public.question_requests'::regclass))
order by c.conrelid::regclass::text, c.conname;

select schemaname, tablename, policyname, cmd, qual, with_check from pg_catalog.pg_policies
where schemaname in ('public','storage') order by schemaname, tablename, policyname;
