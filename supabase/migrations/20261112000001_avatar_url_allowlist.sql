-- =============================================================================
-- 20261112000001_avatar_url_allowlist.sql
-- Hallazgo S-5 (SSRF via profiles.avatar_url). NO APLICADO a produccion:
-- crear el fichero no lo ejecuta; aplicarlo corresponde a un deploy controlado.
--
-- Motivacion: profiles.avatar_url lo escribe cualquier cliente autenticado
-- sobre su propia fila (RLS "update own profile") y get_visible_account_avatars
-- se lo devuelve al resto de la familia, que lo descarga. Sin restriccion en el
-- servidor, cualquier usuario convierte los dispositivos de los demas en un
-- proxy SSRF (metadata cloud, red interna, loopback).
--
-- Un cliente viejo o malicioso puede ignorar la allowlist del cliente (S-5 en
-- lib/services/avatar_url_policy.dart); este CHECK cierra el lado de
-- escritura para todos ellos. A diferencia de un FK con "not valid", un CHECK
-- valida tambien las filas existentes al añadirse, y -validado o no- se aplica
-- a todo DML posterior: no hay ventana.
--
-- El unico productor legitimo es SupabaseAvatarStorageService.uploadAvatar:
--   https://<ref>.supabase.co/storage/v1/object/public/avatars/<uid>/profile?v=<ms>
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Pre-chequeo: filas existentes que no cumplen el patron (debe devolver 0).
-- ---------------------------------------------------------------------------
select id, avatar_url
from public.profiles
where avatar_url is not null
  and avatar_url <> ''
  and avatar_url !~ (
    '^https://hwqvdrtehvixqloegilg\.supabase\.co/storage/v1/object/public/avatars/'
    || id::text
    || '/profile\?v=[0-9]+$'
  );

-- ---------------------------------------------------------------------------
-- CHECK: solo la URL publica del bucket de avatares, y ademas bajo el propio
-- id de la fila (no se puede apuntar al avatar de otra persona). NULL y ''
-- siguen permitidos: es el estado de quien usa un avatar del catalogo local.
-- ---------------------------------------------------------------------------
alter table public.profiles
  drop constraint if exists profiles_avatar_url_storage_only;

alter table public.profiles
  add constraint profiles_avatar_url_storage_only
  check (
    avatar_url is null
    or avatar_url = ''
    or avatar_url ~ (
      '^https://hwqvdrtehvixqloegilg\.supabase\.co/storage/v1/object/public/avatars/'
      || id::text
      || '/profile\?v=[0-9]+$'
    )
  );
