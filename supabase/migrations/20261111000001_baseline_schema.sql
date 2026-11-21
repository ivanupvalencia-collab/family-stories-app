-- =============================================================================
-- 20261111000001_baseline_schema.sql
-- Baseline de esquema exportado del proyecto remoto (2026-11-11).
-- REPRODUCE el estado actual. No cambia semantica con respecto a produccion.
--
-- Correcciones respecto al volcado crudo que genero el exportador:
--   1. Orden de creacion corregido: stories declare FK hacia question_requests
--      pero lo creaba antes. Orden topologico real:
--      profiles -> family_members -> question_requests -> stories
--                -> family_invitations -> family_member_deletions
--   2. Constraint DUPLICADO 'family_invitations_member_owner_fkey' declarado dos
--      veces, la segunda apuntando a family_members(owner_id) que NO tiene
--      UNIQUE (invalido en PostgreSQL). Se elimina: inviter_id ya tiene su FK
--      correcta hacia auth.users(id) ('family_invitations_inviter_fkey').
--
-- Idempotente: cada CREATE TABLE va precedido de DROP TABLE ... IF EXISTS.
-- =============================================================================

drop table if exists public.family_member_deletions cascade;
drop table if exists public.family_invitations cascade;
drop table if exists public.stories cascade;
drop table if exists public.question_requests cascade;
drop table if exists public.family_members cascade;
drop table if exists public.profiles cascade;

-- -----------------------------------------------------------------------------
-- profiles: 1:1 con auth.users. Nunca se inserta desde la app; la crea el
-- trigger handle_new_user (ver 0004).
-- -----------------------------------------------------------------------------
create table public.profiles (
  id uuid not null,
  name text not null,
  avatar_key text,
  avatar_url text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint profiles_pkey primary key (id),
  constraint profiles_id_fkey foreign key (id) references auth.users (id)
);

-- -----------------------------------------------------------------------------
-- family_members: owner_id referencia profiles(id) (no auth.users).
-- linked_account_id solo lo asigna el flujo de invitacion; lo protege el
-- trigger protect_family_member_linked_account (ver 0004).
-- -----------------------------------------------------------------------------
create table public.family_members (
  id uuid not null default gen_random_uuid(),
  owner_id uuid not null,
  name text not null,
  relationship text not null,
  linked_account_id uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  photo_path text,
  constraint family_members_pkey primary key (id),
  constraint family_members_owner_id_fkey foreign key (owner_id)
    references public.profiles (id),
  constraint family_members_linked_account_id_fkey foreign key (linked_account_id)
    references public.profiles (id)
);

-- -----------------------------------------------------------------------------
-- question_requests: se escribe SOLO via RPC send_question_request /
-- complete_question_request. No hay policy de INSERT para authenticated.
-- question_text solo tiene CHECK de no-vacio (ver S-25 en 0007).
-- -----------------------------------------------------------------------------
create table public.question_requests (
  id uuid not null default gen_random_uuid(),
  sender_id uuid not null,
  recipient_id uuid not null,
  family_member_id uuid not null,
  question_text text not null
    check (char_length(trim(both from question_text)) > 0),
  status text not null default 'pending'
    check (status = any (array['pending'::text, 'answered'::text])),
  created_at timestamp with time zone not null default now(),
  answered_at timestamp with time zone,
  constraint question_requests_pkey primary key (id),
  constraint question_requests_sender_id_fkey foreign key (sender_id)
    references auth.users (id),
  constraint question_requests_recipient_id_fkey foreign key (recipient_id)
    references auth.users (id),
  constraint question_requests_family_member_id_fkey foreign key (family_member_id)
    references public.family_members (id)
);

-- -----------------------------------------------------------------------------
-- stories: question_request_id es unica (indice parcial) -> una historia por
-- pregunta. photo_path lo gestiona unicamente set_story_photo (trigger
-- guard_story_photo_path_change, ver 0004).
-- -----------------------------------------------------------------------------
create table public.stories (
  id uuid not null default gen_random_uuid(),
  family_member_id uuid not null,
  question text not null,
  audio_path text not null,
  duration_seconds integer not null check (duration_seconds >= 0),
  created_at timestamp with time zone not null default now(),
  question_request_id uuid,
  recorded_by uuid,
  photo_path text,
  constraint stories_pkey primary key (id),
  constraint stories_family_member_id_fkey foreign key (family_member_id)
    references public.family_members (id),
  constraint stories_question_request_id_fkey foreign key (question_request_id)
    references public.question_requests (id),
  constraint stories_recorded_by_fkey foreign key (recorded_by)
    references auth.users (id)
);

-- -----------------------------------------------------------------------------
-- family_invitations: token_hash = sha256(token) en hex (64 chars). El token en
-- claro (256 bits) solo se devuelve una vez, en create_family_invitation.
-- NOTA: el volcado original declaraba 'family_invitations_member_owner_fkey'
-- dos veces, la segunda con FK a family_members(owner_id) sin UNIQUE -> se
-- descarta. inviter_id conserva su FK correcta a auth.users(id).
-- -----------------------------------------------------------------------------
create table public.family_invitations (
  id uuid not null default gen_random_uuid(),
  family_member_id uuid not null,
  inviter_id uuid not null,
  token_hash text not null unique
    check (token_hash ~ '^[0-9a-f]{64}$'::text),
  status text not null default 'pending'
    check (status = any (array['pending'::text, 'accepted'::text,
                               'cancelled'::text, 'expired'::text])),
  accepted_by uuid,
  created_at timestamp with time zone not null default now(),
  expires_at timestamp with time zone not null default (now() + '7 days'::interval),
  accepted_at timestamp with time zone,
  cancelled_at timestamp with time zone,
  updated_at timestamp with time zone not null default now(),
  constraint family_invitations_pkey primary key (id),
  constraint family_invitations_member_owner_fkey foreign key (family_member_id)
    references public.family_members (id),
  constraint family_invitations_inviter_fkey foreign key (inviter_id)
    references auth.users (id),
  constraint family_invitations_accepted_by_fkey foreign key (accepted_by)
    references auth.users (id)
);

-- -----------------------------------------------------------------------------
-- family_member_deletions: plan de borrado en dos fases (prepare/finish).
-- owner_id referencia auth.users(id) en lugar de profiles(id): inconsistente
-- con el resto pero equivalente por la relacion 1:1. Se mantiene fiel.
-- Acceso solo via RPC (revoke total, ver 0005).
-- -----------------------------------------------------------------------------
create table public.family_member_deletions (
  family_member_id uuid not null,
  owner_id uuid not null,
  resources jsonb not null,
  story_ids jsonb not null,
  completed boolean not null default false,
  created_at timestamp with time zone not null default now(),
  constraint family_member_deletions_pkey primary key (family_member_id),
  constraint family_member_deletions_owner_id_fkey foreign key (owner_id)
    references auth.users (id)
);

-- -----------------------------------------------------------------------------
-- RLS: activo en las 6 tablas (estado real verificado via pg_class).
-- Existe ademas el event trigger rls_auto_enable que lo activa automaticamente
-- en cualquier tabla nueva de public (ver 0004).
-- -----------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.family_members enable row level security;
alter table public.question_requests enable row level security;
alter table public.stories enable row level security;
alter table public.family_invitations enable row level security;
alter table public.family_member_deletions enable row level security;
