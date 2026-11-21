-- Fix the avatar URL CHECK after the photo editor started producing JPEGs.
-- SupabaseAvatarStorageService writes <user-id>/profile.<extension>?v=<ms>.
-- Extensions match privatePhotoExtension and the avatars bucket MIME allowlist.
-- Keep extensionless URLs for avatars saved by older clients.
-- Preserve the exact HTTPS origin, public avatars bucket and row owner id.
-- Replace the constraint in one statement, so failure preserves the old CHECK.
alter table public.profiles
  drop constraint if exists profiles_avatar_url_storage_only,
  add constraint profiles_avatar_url_storage_only
  check (
    avatar_url is null
    or avatar_url = ''
    or avatar_url ~ (
      '^https://hwqvdrtehvixqloegilg\.supabase\.co/storage/v1/object/public/avatars/'
      || id::text
      || '/profile(\.(jpg|png|webp|heic|heif))?\?v=[0-9]+$'
    )
  );
