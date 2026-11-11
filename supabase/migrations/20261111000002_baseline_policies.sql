-- =============================================================================
-- 20261111000002_baseline_policies.sql
-- Politicas RLS exportadas de pg_policies (2026-11-11). Estado actual real.
--
-- Recuento verificado: 6 politicas en public + 24 en storage.objects.
-- NO existe ninguna politica con using (true) ni con acceso blanket.
--
-- Patron de roles observado (conservado tal cual):
--   public.family_members / profiles / stories -> roles {public}
--     Efectivo porque los GRANTS (0005) no dan DML a anon. Redundante pero
--     inofensivo; ver S-30 y nota en 0005.
--   public.question_requests / family_invitations -> roles {authenticated}
--   storage.objects -> roles {authenticated} o {anon} segun politica.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- public.family_members
-- ---------------------------------------------------------------------------
drop policy if exists "Users can read own family members" on public.family_members;
create policy "Users can read own family members"
  on public.family_members for select
  to public
  using (auth.uid() = owner_id);

drop policy if exists "Users can insert own family members" on public.family_members;
create policy "Users can insert own family members"
  on public.family_members for insert
  to public
  with check (auth.uid() = owner_id);

drop policy if exists "Users can update own family members" on public.family_members;
create policy "Users can update own family members"
  on public.family_members for update
  to public
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

drop policy if exists "Users can delete own family members" on public.family_members;
create policy "Users can delete own family members"
  on public.family_members for delete
  to public
  using (auth.uid() = owner_id);

-- ---------------------------------------------------------------------------
-- public.profiles
-- DELETE no tiene politica -> denegado por defecto. La app no borra perfiles.
-- ---------------------------------------------------------------------------
drop policy if exists "Users can read own profile" on public.profiles;
create policy "Users can read own profile"
  on public.profiles for select
  to public
  using (auth.uid() = id);

drop policy if exists "Users can insert own profile" on public.profiles;
create policy "Users can insert own profile"
  on public.profiles for insert
  to public
  with check (auth.uid() = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
  on public.profiles for update
  to public
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- public.stories
-- Scope = owner del familiar. Los RECIPIENTES no tienen acceso directo: leen
-- su respuesta via RPC get_my_answer_story (SECURITY DEFINER).
-- ---------------------------------------------------------------------------
drop policy if exists "Users can read own stories" on public.stories;
create policy "Users can read own stories"
  on public.stories for select
  to public
  using (exists (
    select 1 from public.family_members fm
    where fm.id = stories.family_member_id and fm.owner_id = auth.uid()));

drop policy if exists "Users can insert own stories" on public.stories;
create policy "Users can insert own stories"
  on public.stories for insert
  to public
  with check (exists (
    select 1 from public.family_members fm
    where fm.id = stories.family_member_id and fm.owner_id = auth.uid()));

drop policy if exists "Users can update own stories" on public.stories;
create policy "Users can update own stories"
  on public.stories for update
  to public
  using (exists (
    select 1 from public.family_members fm
    where fm.id = stories.family_member_id and fm.owner_id = auth.uid()));

drop policy if exists "Users can delete own stories" on public.stories;
create policy "Users can delete own stories"
  on public.stories for delete
  to public
  using (exists (
    select 1 from public.family_members fm
    where fm.id = stories.family_member_id and fm.owner_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- public.question_requests
-- Solo SELECT. Escritura exclusivamente via RPC (send/complete_question_request).
-- ---------------------------------------------------------------------------
drop policy if exists "Sender can view own question requests" on public.question_requests;
create policy "Sender can view own question requests"
  on public.question_requests for select
  to authenticated
  using (sender_id = auth.uid());

drop policy if exists "Recipient can view received question requests" on public.question_requests;
create policy "Recipient can view received question requests"
  on public.question_requests for select
  to authenticated
  using (recipient_id = auth.uid());

-- ---------------------------------------------------------------------------
-- public.family_invitations
-- Politica muerta (S-30): authenticated no tiene GRANT de SELECT sobre esta
-- tabla (ver 0005), asi que esta politica nunca se evalua. Se conserva fiel
-- al estado real. La app accede solo via RPC.
-- ---------------------------------------------------------------------------
drop policy if exists "Inviters can view their own invitations" on public.family_invitations;
create policy "Inviters can view their own invitations"
  on public.family_invitations for select
  to authenticated
  using (inviter_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- public.family_member_deletions
-- SIN politicas. RLS activo + revoke total (0005) => denegado a todo rol no
-- postgres/service_role. Acceso unico via prepare/finish_family_member_delete.
-- ---------------------------------------------------------------------------

-- ===========================================================================
-- storage.objects
-- ===========================================================================

-- --- family-member-photos ---------------------------------------------------
drop policy if exists "Owners read family member photos" on storage.objects;
create policy "Owners read family member photos"
  on storage.objects for select
  to authenticated
  using ((bucket_id = 'family-member-photos'::text)
    and ((storage.foldername(name))[1] = ((select auth.uid())::text))
    and exists (select 1 from public.family_members fm
      where (fm.id)::text = (storage.foldername(objects.name))[2]
        and fm.owner_id = (select auth.uid())));

drop policy if exists "Owners upload family member photos" on storage.objects;
create policy "Owners upload family member photos"
  on storage.objects for insert
  to authenticated
  with check ((bucket_id = 'family-member-photos'::text)
    and ((storage.foldername(name))[1] = ((select auth.uid())::text))
    and exists (select 1 from public.family_members fm
      where (fm.id)::text = (storage.foldername(objects.name))[2]
        and fm.owner_id = (select auth.uid())));

drop policy if exists "Owners replace family member photos" on storage.objects;
create policy "Owners replace family member photos"
  on storage.objects for update
  to authenticated
  using ((bucket_id = 'family-member-photos'::text)
    and ((storage.foldername(name))[1] = ((select auth.uid())::text))
    and exists (select 1 from public.family_members fm
      where (fm.id)::text = (storage.foldername(objects.name))[2]
        and fm.owner_id = (select auth.uid())))
  with check ((bucket_id = 'family-member-photos'::text)
    and ((storage.foldername(name))[1] = ((select auth.uid())::text))
    and exists (select 1 from public.family_members fm
      where (fm.id)::text = (storage.foldername(objects.name))[2]
        and fm.owner_id = (select auth.uid())));

drop policy if exists "Owners delete family member photos" on storage.objects;
create policy "Owners delete family member photos"
  on storage.objects for delete
  to authenticated
  using ((bucket_id = 'family-member-photos'::text)
    and ((storage.foldername(name))[1] = ((select auth.uid())::text))
    and exists (select 1 from public.family_members fm
      where (fm.id)::text = (storage.foldername(objects.name))[2]
        and fm.owner_id = (select auth.uid())));

-- Restrictive: exige pertenencia, salvo que el objeto este en un plan de
-- borrado pendiente (family_delete_object_allowed).
drop policy if exists "Family photos require their owner" on storage.objects;
create policy "Family photos require their owner"
  on storage.objects as restrictive for all
  to authenticated
  using ((bucket_id <> 'family-member-photos'::text)
    or (((storage.foldername(name))[1] = ((select auth.uid())::text))
      and exists (select 1 from public.family_members fm
        where (fm.id)::text = (storage.foldername(objects.name))[2]
          and fm.owner_id = (select auth.uid())))
    or family_delete_object_allowed(bucket_id, name))
  with check ((bucket_id <> 'family-member-photos'::text)
    or (((storage.foldername(name))[1] = ((select auth.uid())::text))
      and exists (select 1 from public.family_members fm
        where (fm.id)::text = (storage.foldername(objects.name))[2]
          and fm.owner_id = (select auth.uid()))));

drop policy if exists "Family photos deny anonymous access" on storage.objects;
create policy "Family photos deny anonymous access"
  on storage.objects as restrictive for all
  to anon
  using (bucket_id <> 'family-member-photos'::text)
  with check (bucket_id <> 'family-member-photos'::text);

-- --- story-photos -----------------------------------------------------------
drop policy if exists "Participants read story photos" on storage.objects;
create policy "Participants read story photos"
  on storage.objects for select
  to authenticated
  using ((bucket_id = 'story-photos'::text)
    and story_photo_allowed(name, 'read'::text));

drop policy if exists "Participants upload story photos" on storage.objects;
create policy "Participants upload story photos"
  on storage.objects for insert
  to authenticated
  with check ((bucket_id = 'story-photos'::text)
    and story_photo_allowed(name, 'insert'::text));

drop policy if exists "Participants clean inactive story photos" on storage.objects;
create policy "Participants clean inactive story photos"
  on storage.objects for delete
  to authenticated
  using ((bucket_id = 'story-photos'::text)
    and story_photo_allowed(name, 'delete'::text));

drop policy if exists "Story photo read guard" on storage.objects;
create policy "Story photo read guard"
  on storage.objects as restrictive for select
  to authenticated
  using ((bucket_id <> 'story-photos'::text)
    or story_photo_allowed(name, 'read'::text)
    or family_delete_object_allowed(bucket_id, name));

drop policy if exists "Story photo insert guard" on storage.objects;
create policy "Story photo insert guard"
  on storage.objects as restrictive for insert
  to authenticated
  with check ((bucket_id <> 'story-photos'::text)
    or story_photo_allowed(name, 'insert'::text));

-- Sin policy permisiva de UPDATE en story-photos: las referencias se cambian
-- unicamente via set_story_photo (SECURITY DEFINER). Este restrictive bloquea
-- cualquier intento directo.
drop policy if exists "Story photo update guard" on storage.objects;
create policy "Story photo update guard"
  on storage.objects as restrictive for update
  to authenticated
  using (bucket_id <> 'story-photos'::text)
  with check (bucket_id <> 'story-photos'::text);

drop policy if exists "Story photo delete guard" on storage.objects;
create policy "Story photo delete guard"
  on storage.objects as restrictive for delete
  to authenticated
  using ((bucket_id <> 'story-photos'::text)
    or story_photo_allowed(name, 'delete'::text)
    or family_delete_object_allowed(bucket_id, name));

drop policy if exists "Story photos deny anonymous" on storage.objects;
create policy "Story photos deny anonymous"
  on storage.objects as restrictive for all
  to anon
  using (bucket_id <> 'story-photos'::text)
  with check (bucket_id <> 'story-photos'::text);

-- --- story-audio ------------------------------------------------------------
-- NOTA (S-23): este bucket NO tiene deny-anon ni politica restrictiva. Queda
-- cubierto porque todas sus politicas permisivas son 'to authenticated', y sin
-- politica permisiva anon no ve nada. Se anade deny-anon en 0007.
drop policy if exists "Family owners can read response audio" on storage.objects;
create policy "Family owners can read response audio"
  on storage.objects for select
  to authenticated
  using ((bucket_id = 'story-audio'::text)
    and exists (select 1
      from (public.question_requests qr
        join public.family_members fm on fm.id = qr.family_member_id)
      where ((qr.id)::text = (storage.foldername(objects.name))[1])
        and fm.owner_id = auth.uid()));

drop policy if exists "Responders can read own response audio" on storage.objects;
create policy "Responders can read own response audio"
  on storage.objects for select
  to authenticated
  using ((bucket_id = 'story-audio'::text)
    and exists (select 1 from public.question_requests qr
      where ((qr.id)::text = (storage.foldername(objects.name))[1])
        and qr.recipient_id = auth.uid()));

drop policy if exists "Recipients can upload question response audio" on storage.objects;
create policy "Recipients can upload question response audio"
  on storage.objects for insert
  to authenticated
  with check ((bucket_id = 'story-audio'::text)
    and exists (select 1 from public.question_requests qr
      where ((qr.id)::text = (storage.foldername(objects.name))[1])
        and qr.recipient_id = auth.uid()
        and qr.status = 'pending'::text));

-- --- avatars ----------------------------------------------------------------
-- Bucket PUBLICO (ver 0005). Sin policy de DELETE (S-29).
drop policy if exists "Users can select their own avatar" on storage.objects;
create policy "Users can select their own avatar"
  on storage.objects for select
  to authenticated
  using ((bucket_id = 'avatars'::text)
    and ((storage.foldername(name))[1] = ((select auth.uid())::text)));

drop policy if exists "Users can insert their own avatar" on storage.objects;
create policy "Users can insert their own avatar"
  on storage.objects for insert
  to authenticated
  with check ((bucket_id = 'avatars'::text)
    and ((storage.foldername(name))[1] = ((select auth.uid())::text)));

drop policy if exists "Users can update their own avatar" on storage.objects;
create policy "Users can update their own avatar"
  on storage.objects for update
  to authenticated
  using ((bucket_id = 'avatars'::text)
    and ((storage.foldername(name))[1] = ((select auth.uid())::text)))
  with check ((bucket_id = 'avatars'::text)
    and ((storage.foldername(name))[1] = ((select auth.uid())::text)));

-- --- plan de borrado familiar (cualquier bucket) ----------------------------
drop policy if exists "Owner deletion plan reads resources" on storage.objects;
create policy "Owner deletion plan reads resources"
  on storage.objects for select
  to authenticated
  using (family_delete_object_allowed(bucket_id, name));

drop policy if exists "Owner deletion plan removes resources" on storage.objects;
create policy "Owner deletion plan removes resources"
  on storage.objects for delete
  to authenticated
  using (family_delete_object_allowed(bucket_id, name));

-- --- escrituras bloqueadas durante un borrado pendiente ---------------------
drop policy if exists "Pending family deletion blocks uploads" on storage.objects;
create policy "Pending family deletion blocks uploads"
  on storage.objects as restrictive for insert
  to authenticated
  with check (family_delete_storage_write_allowed(bucket_id, name));

drop policy if exists "Pending family deletion blocks replacements" on storage.objects;
create policy "Pending family deletion blocks replacements"
  on storage.objects as restrictive for update
  to authenticated
  using (family_delete_storage_write_allowed(bucket_id, name))
  with check (family_delete_storage_write_allowed(bucket_id, name));
