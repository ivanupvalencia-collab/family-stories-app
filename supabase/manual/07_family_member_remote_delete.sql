-- MANUAL ONLY. Requires installed 01/02, 03/04 FINAL and 05, and audited CASCADE FKs.
-- Do NOT enable Flutter deletion until installation has been explicitly confirmed.
-- No blob or storage.objects row is ever deleted by this script or its RPCs.
begin;

-- Private, durable retry journal. Completed rows are ownership tombstones so
-- a lost final RPC response can be retried safely. No client table access.
create table if not exists public.family_member_deletions (
  family_member_id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  resources jsonb not null,
  story_ids jsonb not null,
  completed boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.family_member_deletions enable row level security;
revoke all on public.family_member_deletions from public, anon, authenticated;

create or replace function public.family_delete_object_allowed(p_bucket text, p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from public.family_member_deletions d
    join public.family_members fm on fm.id = d.family_member_id
    where d.owner_id = auth.uid() and fm.owner_id = auth.uid() and not d.completed
      and exists (select 1 from jsonb_array_elements(d.resources) r
        where r->>'bucket' = p_bucket and r->>'path' = p_name)
  );
$$;

-- Serialize object metadata INSERT/UPDATE with preparation. Resolve folders
-- against authoritative rows; the guard supplies no positive upload permission.
create or replace function public.family_delete_storage_write_allowed(p_bucket text, p_name text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare v_member uuid;
begin
  if p_bucket = 'family-member-photos' then
    select fm.id into v_member from public.family_members fm
      where fm.owner_id::text = split_part(p_name,'/',1)
        and fm.id::text = split_part(p_name,'/',2);
  elsif p_bucket = 'story-photos' then
    select s.family_member_id into v_member from public.stories s
      where s.id::text = split_part(p_name,'/',2);
  elsif p_bucket = 'story-audio' then
    select qr.family_member_id into v_member from public.question_requests qr
      where qr.id::text = split_part(p_name,'/',1);
    if v_member is null then
      select s.family_member_id into v_member from public.stories s
        where s.audio_path = p_name limit 1;
    end if;
  end if;
  if v_member is null then return true; end if;
  perform 1 from public.family_members where id = v_member for update;
  return not exists (select 1 from public.family_member_deletions
    where family_member_id = v_member);
end $$;

create or replace function public.guard_family_delete_child()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_member uuid; v_new_member uuid;
begin
  if TG_OP <> 'INSERT' then v_member := (to_jsonb(OLD)->>TG_ARGV[0])::uuid; end if;
  if TG_OP <> 'DELETE' then v_new_member := (to_jsonb(NEW)->>TG_ARGV[0])::uuid; end if;
  -- Lock both parents for moves; changing a client-provided FK cannot bypass
  -- the freeze of the old family. During CASCADE the parent no longer exists.
  perform id from public.family_members
    where id in (v_member, v_new_member) order by id for update;
  if exists (select 1 from public.family_member_deletions d
      join public.family_members fm on fm.id = d.family_member_id
      where d.family_member_id in (v_member, v_new_member)) then
    raise exception 'Family member deletion is in progress' using errcode = '55000';
  end if;
  if TG_OP = 'DELETE' then return OLD; end if;
  return NEW;
end $$;

create or replace function public.guard_family_delete_parent()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_resources jsonb;
begin
  if TG_OP = 'INSERT' then
    if exists (select 1 from public.family_member_deletions where family_member_id = NEW.id) then
      raise exception 'Deleted family ID cannot be reused' using errcode = '55000';
    end if;
    return NEW;
  end if;
  if TG_OP = 'UPDATE' then
    if exists (select 1 from public.family_member_deletions where family_member_id = OLD.id) then
      raise exception 'Family member deletion is in progress' using errcode = '55000';
    end if;
    return NEW;
  end if;
  if OLD.owner_id is distinct from auth.uid() then
    raise exception 'Only the family owner may delete' using errcode = '42501';
  end if;
  select resources into v_resources from public.family_member_deletions
    where family_member_id = OLD.id and owner_id = auth.uid() and completed;
  if not found then
    raise exception 'Prepare deletion first' using errcode = '55000';
  end if;
  if exists (select 1 from storage.objects o
      join jsonb_array_elements(v_resources) r
        on o.bucket_id = r->>'bucket' and o.name = r->>'path') then
    raise exception 'Storage cleanup is incomplete' using errcode = '55000';
  end if;
  return OLD;
end $$;

drop trigger if exists family_delete_parent_guard on public.family_members;
create trigger family_delete_parent_guard before insert or update or delete on public.family_members
  for each row execute function public.guard_family_delete_parent();
do $$ declare t text; v_columns text[]; v_valid boolean; begin
  foreach t in array array['stories','question_requests','family_invitations'] loop
    -- Match each child/parent column pair by its position in the FK. This
    -- supports both a simple member FK and invitations' composite FK
    -- (family_member_id, inviter_id) -> (id, owner_id), in either column order.
    -- Only the child paired with family_members.id identifies the member.
    -- Inspect all such FKs (not just CASCADE ones), without DISTINCT, so an
    -- additional mapping cannot silently hide an ambiguous relationship.
    select array_agg(child.attname::text),
      bool_and(c.confdeltype = 'c' and c.convalidated
        and child.atttypid = parent.atttypid
        and parent.atttypid = 'pg_catalog.uuid'::regtype)
      into v_columns, v_valid
      from pg_catalog.pg_constraint c
      cross join lateral pg_catalog.generate_subscripts(c.conkey,1) k(position)
      join pg_catalog.pg_attribute child
        on child.attrelid = c.conrelid and child.attnum = c.conkey[k.position]
        and not child.attisdropped
      join pg_catalog.pg_attribute parent
        on parent.attrelid = c.confrelid and parent.attnum = c.confkey[k.position]
        and not parent.attisdropped
      where c.contype = 'f' and c.conrelid = format('public.%I',t)::regclass
        and c.confrelid = 'public.family_members'::regclass
        and parent.attname = 'id';
    if coalesce(cardinality(v_columns),0) <> 1 or v_valid is distinct from true then
      raise exception 'Expected one unambiguous validated CASCADE FK mapping to family_members.id (uuid) on %',t;
    end if;
    execute format('drop trigger if exists family_delete_child_guard on public.%I',t);
    execute format('create trigger family_delete_child_guard before insert or update or delete on public.%I for each row execute function public.guard_family_delete_child(%L)',t,v_columns[1]);
  end loop;
end $$;

create or replace function public.prepare_family_member_delete(p_family_member_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_owner uuid; v_plan public.family_member_deletions%rowtype;
  v_resources jsonb; v_stories jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select owner_id into v_owner from public.family_members where id = p_family_member_id for update;
  if not found then
    select * into v_plan from public.family_member_deletions
      where family_member_id = p_family_member_id and owner_id = auth.uid() and completed;
    if not found then raise exception 'Family member unavailable' using errcode = '42501'; end if;
    return jsonb_build_object('resources',v_plan.resources,'story_ids',v_plan.story_ids);
  end if;
  if v_owner is distinct from auth.uid() then raise exception 'Only the family owner may delete' using errcode = '42501'; end if;
  select * into v_plan from public.family_member_deletions where family_member_id = p_family_member_id;
  if found then
    if v_plan.owner_id is distinct from auth.uid() or v_plan.completed then
      raise exception 'Owner deletion plan required' using errcode = '42501';
    end if;
    return jsonb_build_object('resources',v_plan.resources,'story_ids',v_plan.story_ids);
  end if;
  perform id from public.stories where family_member_id = p_family_member_id for update;
  perform id from public.question_requests where family_member_id = p_family_member_id for update;
  -- Reject ambiguous legacy audio references rather than deleting another family's object.
  if exists (select 1 from public.stories s join public.stories other
      on other.audio_path = s.audio_path and other.family_member_id <> s.family_member_id
      where s.family_member_id = p_family_member_id and s.audio_path is not null) then
    raise exception 'Audio is shared with another family member; manual review required' using errcode = '55000';
  end if;
  select coalesce(jsonb_agg(id::text),'[]'::jsonb) into v_stories
    from public.stories where family_member_id = p_family_member_id;
  -- Actual references plus existing objects in the app's verified namespaces.
  -- Include inactive/staged objects, not just the currently visible photos.
  with targets(bucket,path) as (
    select 'family-member-photos',photo_path from public.family_members where id = p_family_member_id
    union select 'story-photos',photo_path from public.stories where family_member_id = p_family_member_id
    union select 'story-audio',audio_path from public.stories where family_member_id = p_family_member_id
    union select o.bucket_id,o.name from storage.objects o where
      (o.bucket_id = 'family-member-photos' and split_part(o.name,'/',1) = v_owner::text
        and split_part(o.name,'/',2) = p_family_member_id::text)
      or (o.bucket_id = 'story-photos' and exists (select 1 from public.stories s
        where s.family_member_id = p_family_member_id and s.id::text = split_part(o.name,'/',2)))
      or (o.bucket_id = 'story-audio' and exists (select 1 from public.question_requests qr
        where qr.family_member_id = p_family_member_id and qr.id::text = split_part(o.name,'/',1)))
  ) select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket,'path',path) order by bucket,path),'[]'::jsonb)
    into v_resources from targets where path is not null and path <> '';
  if exists (select 1 from jsonb_array_elements(v_resources) r join public.stories s
      on r->>'bucket' = 'story-audio' and r->>'path' = s.audio_path
      where s.family_member_id <> p_family_member_id) then
    raise exception 'Audio namespace is shared; manual review required' using errcode = '55000';
  end if;
  -- Detach active photo references transactionally BEFORE allowing deletion.
  -- Existing set_story_photo/set_family_member_photo RPCs subsequently hit the
  -- triggers; neither recorder nor owner can revive a reference during cleanup.
  -- Match 04 FINAL: open 03 FINAL's guard transaction-locally, only around
  -- this owner-authorized UPDATE, and close it before any other write.
  perform pg_catalog.set_config('app.story_photo_rpc', '1', true);
  update public.stories set photo_path = null where family_member_id = p_family_member_id and photo_path is not null;
  perform pg_catalog.set_config('app.story_photo_rpc', '', true);
  update public.family_members set photo_path = null where id = p_family_member_id and photo_path is not null;
  insert into public.family_member_deletions(family_member_id,owner_id,resources,story_ids)
    values(p_family_member_id,v_owner,v_resources,v_stories);
  return jsonb_build_object('resources',v_resources,'story_ids',v_stories);
end $$;

create or replace function public.finish_family_member_delete(p_family_member_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_owner uuid; v_plan public.family_member_deletions%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select owner_id into v_owner from public.family_members where id = p_family_member_id for update;
  select * into v_plan from public.family_member_deletions
    where family_member_id = p_family_member_id and owner_id = auth.uid() for update;
  if not found then raise exception 'Owner deletion plan required' using errcode = '42501'; end if;
  if v_plan.completed then return; end if;
  if v_owner is distinct from auth.uid() then raise exception 'Only the family owner may delete' using errcode = '42501'; end if;
  -- A client cannot set this private flag or DELETE directly after preparation.
  -- The flag and CASCADE are in one transaction; trigger failure rolls it back.
  update public.family_member_deletions set completed = true where family_member_id = p_family_member_id;
  -- Parent trigger independently verifies every Storage metadata row is gone.
  delete from public.family_members where id = p_family_member_id and owner_id = auth.uid();
end $$;

-- Only server-snapshotted objects of an owner-authorized pending deletion.
-- SELECT is necessary for Storage's DELETE filtering, including recorder uploads.
drop policy if exists "Owner deletion plan reads resources" on storage.objects;
create policy "Owner deletion plan reads resources" on storage.objects for select to authenticated
  using (public.family_delete_object_allowed(bucket_id,storage.objects.name));
drop policy if exists "Owner deletion plan removes resources" on storage.objects;
create policy "Owner deletion plan removes resources" on storage.objects for delete to authenticated
  using (public.family_delete_object_allowed(bucket_id,storage.objects.name));

-- Preserve installed FINAL policy expressions, including their active-photo
-- safeguards. Add an exception ONLY for this owner's authoritative snapshot.
-- Restrictive policies otherwise veto the new narrow permissive policies.
-- Does not replace helpers/RPCs from FINAL or expand general story SELECT.
do $$ declare p record; begin
  for p in select pol.polname,pg_get_expr(pol.polqual,pol.polrelid) expr
      from pg_catalog.pg_policy pol
      where pol.polrelid = 'storage.objects'::regclass and not pol.polpermissive
        and pol.polcmd in ('r','d','*') and pol.polqual is not null
        and (0::oid = any(pol.polroles) or 'authenticated'::regrole::oid = any(pol.polroles)) loop
    if position('family_delete_object_allowed' in p.expr) = 0 then
      execute format('alter policy %I on storage.objects using ((%s) or public.family_delete_object_allowed(bucket_id,storage.objects.name))',p.polname,p.expr);
    end if;
  end loop;
end $$;
drop policy if exists "Pending family deletion blocks uploads" on storage.objects;
create policy "Pending family deletion blocks uploads" on storage.objects as restrictive for insert to authenticated
  with check (public.family_delete_storage_write_allowed(bucket_id,storage.objects.name));
drop policy if exists "Pending family deletion blocks replacements" on storage.objects;
create policy "Pending family deletion blocks replacements" on storage.objects as restrictive for update to authenticated
  using (public.family_delete_storage_write_allowed(bucket_id,storage.objects.name))
  with check (public.family_delete_storage_write_allowed(bucket_id,storage.objects.name));

revoke all on function public.family_delete_object_allowed(text,text),
  public.family_delete_storage_write_allowed(text,text),
  public.guard_family_delete_child(), public.guard_family_delete_parent(),
  public.prepare_family_member_delete(uuid),public.finish_family_member_delete(uuid) from public,anon,authenticated;
grant execute on function public.family_delete_object_allowed(text,text),
  public.family_delete_storage_write_allowed(text,text),
  public.prepare_family_member_delete(uuid),public.finish_family_member_delete(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
