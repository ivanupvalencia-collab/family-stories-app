-- =============================================================================
-- 20261111000006_indexes.sql
-- Seccion A: indices EXISTENTES exportados de pg_indexes (estado real).
-- Seccion B: 6 indices NUEVOS que cierran el hallazgo C-3.
--
-- CORRECCION A LA AUDITORIA: se habia afirmado "cero indices en todo el
-- proyecto". Eso era cierto en el REPO (ningun CREATE INDEX versionado), pero
-- la base de datos SI tenia indices. El hueco real es question_requests
-- (solo pkey) y family_member_deletions (sin ninguno).
--
-- Seccion A es un no-op si los indices ya existen (create index if not exists).
-- =============================================================================

-- ===========================================================================
-- SECCION A - indices existentes (baseline)
-- ===========================================================================
create unique index if not exists profiles_pkey
  on public.profiles using btree (id);

create unique index if not exists family_members_pkey
  on public.family_members using btree (id);

create index if not exists family_members_owner_id_idx
  on public.family_members using btree (owner_id);

create unique index if not exists family_members_id_owner_id_uidx
  on public.family_members using btree (id, owner_id);

create unique index if not exists question_requests_pkey
  on public.question_requests using btree (id);

create unique index if not exists stories_pkey
  on public.stories using btree (id);

create index if not exists stories_family_member_id_idx
  on public.stories using btree (family_member_id);

create unique index if not exists stories_question_request_id_unique
  on public.stories using btree (question_request_id)
  where (question_request_id is not null);

create unique index if not exists family_invitations_pkey
  on public.family_invitations using btree (id);

create unique index if not exists family_invitations_token_hash_key
  on public.family_invitations using btree (token_hash);

create unique index if not exists family_invitations_one_pending_per_member_uidx
  on public.family_invitations using btree (family_member_id)
  where (status = 'pending'::text);

create index if not exists family_invitations_inviter_created_idx
  on public.family_invitations using btree (inviter_id, created_at desc);

create index if not exists family_invitations_member_created_idx
  on public.family_invitations using btree (family_member_id, created_at desc);

create index if not exists family_invitations_pending_expiration_idx
  on public.family_invitations using btree (expires_at)
  where (status = 'pending'::text);

create index if not exists family_invitations_accepted_by_idx
  on public.family_invitations using btree (accepted_by)
  where (accepted_by is not null);

create unique index if not exists family_member_deletions_pkey
  on public.family_member_deletions using btree (family_member_id);

-- ===========================================================================
-- SECCION B - 6 indices nuevos (C-3)
-- ===========================================================================
-- 1. Home carga DOS listas de question_requests filtrando por recipient_id +
--    status y ordenando por created_at. Hoy: seq scan + sort en cada refresh.
create index if not exists question_requests_recipient_status_created_idx
  on public.question_requests using btree (recipient_id, status, created_at desc);

-- 2. Segunda lista de Home: orden por answered_at desc nulls last.
--    (No existe nulls last en un indice btree estandar; el orden de columna
--    sigue ayudando al planner a reducir el sort.)
create index if not exists question_requests_recipient_status_answered_idx
  on public.question_requests using btree (recipient_id, status, answered_at desc);

-- 3. get_visible_account_avatars hace una subquery
--    qr.recipient_id = auth.uid() and qr.sender_id = p.id.
--    Cubre la parte sender_id (recipient_id ya lo cubre el indice 1).
create index if not exists question_requests_sender_id_idx
  on public.question_requests using btree (sender_id);

-- 4. get_visible_account_avatars hace
--    fm.owner_id = auth.uid() and fm.linked_account_id = p.id.
--    Sin indice, escanea todos los familiares del usuario en cada llamada.
create index if not exists family_members_linked_account_id_idx
  on public.family_members using btree (linked_account_id)
  where (linked_account_id is not null);

-- 5. family_delete_object_allowed evalua d.owner_id = auth.uid() POR CADA
--    objeto de storage que se toca (politicas de storage.objects).
--    family_member_deletions es pequena hoy, pero la evaluacion es por fila
--    de storage, no por fila de la tabla: sin indice es seq scan repetido.
create index if not exists family_member_deletions_owner_id_idx
  on public.family_member_deletions using btree (owner_id);

-- 6. Reemplaza stories_family_member_id_idx para el caso de uso real:
--    .eq('family_member_id', x).order('created_at', descending).
--    Con el indice simple hay que ordenar en memoria; con el compuesto no.
--    Se mantiene el indice simple (A) por si otros planificadores lo prefieren;
--    si se quiere eliminar, hacerlo en una migracion posterior.
create index if not exists stories_family_member_created_idx
  on public.stories using btree (family_member_id, created_at desc);
