# supabase/

Este directorio contiene dos cosas distintas. No confundirlas:

| Directorio | Qué es | Estado |
|---|---|---|
| `migrations/` | **Baseline fiel** del esquema, RLS, funciones, triggers, grants e índices del proyecto remoto, más las correcciones de hardening | Nuevo (2026-11-11) |
| `manual/` | Scripts que se instalaron **a mano** en su día, con su documentación | Histórico, **no tocar** |

## migrations/

Exportado completo desde el proyecto remoto el 2026-11-11 mediante `pg_class`,
`pg_policies`, `pg_proc`, `pg_trigger`, `pg_indexes`,
`information_schema.role_table_grants` y `storage.buckets`.

### Orden de aplicación

```
000001_baseline_schema.sql      6 tablas en orden topológico, RLS habilitado
000002_baseline_policies.sql    5 helpers de storage + 6 políticas public + 24 en storage.objects
000003_baseline_functions.sql   26 funciones (incluye las 6 RPC que faltaban)
000004_baseline_triggers.sql    8 triggers de tabla + event trigger rls_auto_enable
000005_baseline_grants.sql      grants por rol + 4 buckets
000006_indexes.sql              A: 16 índices existentes · B: 6 índices nuevos (C-3)
000007_hardening.sql            ⚠️ SÍ cambia estado: S-23, S-24, S-25, S-31
20261112000001_avatar_url_allowlist.sql  ⚠️ SÍ cambia estado: CHECK en profiles.avatar_url (S-5) · NO aplicado
20261113000001_text_limits.sql            ⚠️ SÍ cambia estado: CHECK en family_members.name ≤ 200 (S-13) · NO aplicado
20261114000001_updated_at_triggers.sql    ⚠️ SÍ cambia estado: triggers set_updated_at en profiles/family_members (S-27) · NO aplicado
20261115000001_avatar_delete_policy.sql   ⚠️ SÍ cambia estado: política DELETE own-folder en avatars (S-29) · NO aplicado
20261116000001_drop_dead_invitation_policy.sql  ⚠️ SÍ cambia estado: DROP de la política muerta en family_invitations (S-30) · NO aplicado
```

**0001–0006 son un no-op** sobre el proyecto vivo: reproducen el estado actual
(`create or replace`, `drop policy if exists`, `create index if not exists`),
**con tres excepciones puntuales ya corregidas en el propio volcado**: el cuerpo
de `get_story_photo_metadata` (`can_edit` calculado, S-19), el de
`get_family_invitation_preview` (sin `FOR UPDATE`, S-28) y las 10 políticas de
storage de `0002`, que delegan en los helpers `family_member_photo_allowed` y
`response_audio_allowed` (C-4: mismo comportamiento RLS, plan con índice). Los
cinco helpers de storage (`story_photo_allowed`, `family_member_photo_allowed`,
`response_audio_allowed`, `family_delete_object_allowed`,
`family_delete_storage_write_allowed`) se definen ahora AL PRINCIPIO de `0002`,
antes de las políticas: `create policy` resuelve la función al crearse y tiene
que existir previamente — fue el fallo de la primera sincronización con GitHub
(2026-11-21, SQLSTATE 42883) —; `0003` los re-crea idempotentemente con
`create or replace`; al aplicarlos con `create or replace`/`drop policy if exists` cambian esos
cuerpos y políticas con resultado acotado.
**0007 sí modifica el proyecto**: revoca `TRUNCATE`, limita buckets y añade el
límite de `question_text`. **0008 (S-5) añade un `CHECK` a `profiles.avatar_url`
y todavía NO se ha aplicado a producción**: incluye un `select` de pre-chequeo
que debe devolver 0 filas antes del `add constraint`. **0009 (S-13) añade el
`CHECK` de `family_members.name`** (NOT VALID + validate con aviso, igual que
el de `question_text`) y tampoco se ha aplicado. **0010 (S-27) crea los
triggers de `updated_at`**, **0011 (S-29) la política `DELETE` de `avatars`**
y **0012 (S-30) elimina la política muerta de `family_invitations`**; ninguno
se ha aplicado.

### Compatibilidad de URL de avatar (2026-11-21)

`20261121000001_avatar_url_image_extensions.sql` sustituye el CHECK
`profiles_avatar_url_storage_only`: conserva `profile?v=<ms>` y permite
`profile.jpg`, `profile.png`, `profile.webp`, `profile.heic` y `profile.heif`
con la misma revisión `?v=<ms>`. Son las extensiones que generan los servicios
de fotos y cuyos MIME ya admite el bucket `avatars`. Sigue exigiendo HTTPS,
el host exacto del proyecto, el bucket público `avatars` y la carpeta del `id`
de la propia fila. Mantiene los valores NULL/vacío del catálogo de avatares.
La sustitución se hace en una única sentencia y valida las filas existentes.

La prueba `test/avatar_url_migration_test.dart` reproduce que el patrón anterior
rechaza `profile.jpg?v=...` y comprueba los formatos permitidos y las URL que
deben rechazarse. Es una comprobación estática; no acredita qué migraciones
están instaladas en el proyecto remoto.

#### Aplicación mediante la integración existente con GitHub

Este documento registra sincronizaciones previas con GitHub. El repositorio
no contiene `.github/workflows/`, `supabase/config.toml` ni un script de deploy;
la configuración de la integración y el historial aplicado están fuera de Git.
Las anotaciones históricas «NO aplicado» de arriba no prueban el estado remoto
actual.

1. Revisar en la integración GitHub de Supabase que este repositorio y la rama
   de producción sean los correctos, y que `Deploy to production` esté activo.
2. Incorporar la nueva migración al flujo habitual de rama/PR y merge a la rama
   de producción configurada (`main` si conserva la rama principal del repo).
3. Revisar el despliegue de Supabase: la fase `migrate` debe aplicar
   `20261121000001` y terminar correctamente. Después, reintentar guardar el
   avatar desde la app. No hace falta cambiar ni recompilar el cliente.

La integración aplica los archivos que no figuran en su historial de migraciones:
antes del merge, comprobar que el baseline ya está registrado y que las
pendientes son las esperadas. No reiniciar la base ni volver a ejecutar el
baseline sobre producción: `20261111000001_baseline_schema.sql` contiene
`DROP TABLE`. Si hay una migración anterior fallida, debe resolverse mediante
el mismo flujo antes de que pueda ejecutarse esta nueva.

Referencia: [integración GitHub de Supabase](https://supabase.com/docs/guides/deployment/branching/github-integration).

### Correcciones sobre el volcado crudo

El exportador del dashboard devolvió tres defectos que `0001` corrige:

1. **Orden inválido** — `stories` declaraba FK hacia `question_requests`
   creándolo antes.
2. **Constraint duplicado** — `family_invitations_member_owner_fkey` aparecía
   dos veces, la segunda apuntando a `family_members(owner_id)` que no tiene
   `UNIQUE` (inválido en PostgreSQL). `inviter_id` conserva su FK correcta a
   `auth.users(id)`.
3. **Sin entorno de autorización** — el volcado solo traía `CREATE TABLE`.

> Un defecto ajeno al volcado afloró en la segunda sincronización con GitHub
> (2026-11-21): `0005`/`0007` escribían `allowed_mime_types` con `'...'::jsonb`,
> pero la columna de `storage.buckets` es `text[]` (también en upstream);
> SQLSTATE 42804. Corregido con arrays nativos en ambos ficheros.

### Resumen de la postura de seguridad verificada

- Las **6 tablas tienen RLS activo** y **no existe ninguna política
  `using (true)`**.
- Las 26 funciones `SECURITY DEFINER` llevan `SET search_path TO ''`.
- `question_requests`, `family_invitations` y `family_member_deletions` **no
  tienen grants de DML** para `authenticated`: se accede solo por RPC.
- Existe un **event trigger `rls_auto_enable`** que activa RLS en cualquier
  tabla nueva de `public`.
- El trigger `protect_family_member_linked_account` impide que el cliente asigne
  `linked_account_id` fuera del flujo de invitación.
- Tokens de invitación: **256 bits aleatorios**, almacenados como `sha256`,
  expiración a 7 días, un único `pending` por familiar (índice unique),
  serialización con `FOR UPDATE`.

### Hallazgos abiertos tras la exportación

El índice completo de la auditoría (S-, A-, C-) vive en
[`docs/AUDITORIA.md`](../docs/AUDITORIA.md); aquí solo se listan los que
afectan a este directorio.

| ID | Hallazgo | Estado |
|---|---|---|
| S-1 | Esquema + RLS no versionados | ✅ resuelto con `migrations/` |
| S-3 | Sesión Supabase en SharedPreferences en claro | ✅ resuelto en la app (`secure_session_storage.dart`) |
| S-5 | `profiles.avatar_url` es URL libre → SSRF on-device | ✅ allowlist en la app · `20261112000001` **pendiente de aplicar** |
| S-8 | Flag de borrado remoto activo sin gate auditado | ✅ gate en `test/deletion_sql_gate_test.dart` + `tool/lint_rls.sh`: flag `true` ⇒ RPCs `prepare`/`finish_family_member_delete` en `migrations/` |
| S-13 | `family_members.name` sin límite (el alta va por INSERT directo) | ✅ `maxLength` 200 en la UI · `20261113000001` **pendiente de aplicar** |
| S-17 | `manual/07` reescribía políticas ajenas con `execute format('alter policy ...')` | ✅ 3 `alter policy` explícitos en `07` · gate S-17 en `tool/lint_rls.sh` (ambos modos) |
| S-19 | `get_story_photo_metadata` devuelve `can_edit` siempre `true` | ✅ `can_edit` calculado con el predicado owner/recorder en `0003` · gate S-19 en `tool/lint_rls.sh` (`manual/04` histórico exento) |
| S-23 | Buckets sin límite de tipo/tamaño | ✅ `0007` |
| S-24 | `TRUNCATE` para `anon`/`authenticated` | ✅ `0007` |
| S-25 | `question_text` sin límite superior | ✅ `0007` |
| S-27 | `updated_at` sin trigger (solo `family_invitations` lo tenía) | ✅ `20261114000001` **pendiente de aplicar** (triggers en `profiles`/`family_members`) · gate S-27 en `tool/lint_rls.sh` |
| S-28 | `get_family_invitation_preview` hace `FOR UPDATE` en una lectura | ✅ lectura sin lock en `0003` · gate S-28 en `tool/lint_rls.sh` |
| S-29 | Bucket `avatars` sin política `DELETE` (fail-closed; huérfanos públicos al revertir a catálogo) | ✅ `20261115000001` **pendiente de aplicar** (own-folder) · gate S-29 |
| S-30 | Política muerta `Inviters can view their own invitations` | ✅ `20261116000001` **pendiente de aplicar** (drop sin efecto observable) · gate S-30 |
| C-4 | Casts `fm.id::text` bloquean el índice en políticas de storage | ✅ 10 expresiones de `0002` → helpers `family_member_photo_allowed`/`response_audio_allowed` en `0003` · gate C-4 · verificado en Postgres local (docker): de seq scan a `Index Scan using …_pkey`; **pendiente de prueba en producción** |

## manual/

Los 15 scripts siguen siendo válidos y **ya están reflejados en `migrations/`**.
En un entorno nuevo basta con `migrations/`; `manual/` queda como registro
histórico de la instalación original y como referencia de su documentación
(`FAMILY_MEMBER_PHOTOS.md`, `ARITORIA_HOME.md`, `ACCOUNT_AVATARS.md`…).

> `supabase/manual/README.md` ya no afirma que el esquema base "no está
> versionado en este repositorio": se corrigió en `b878d8c`.

## Cómo verificar que el baseline sigue fiel

```sql
-- Política sospechosa (debe devolver 0 filas)
select * from pg_policies
where schemaname in ('public','storage')
  and (qual = 'true' or with_check = 'true');

-- Tablas sin RLS (debe devolver 0 filas)
select c.relname from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;

-- Funciones SECURITY DEFINER sin revoke (debe devolver 0 filas)
select p.proname from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
  and (p.proacl is null or p.proacl::text like '%=X/postgres%')
  and p.proname not in ('handle_new_user','rls_auto_enable');
```

El script `tool/lint_rls.sh` automatiza estas comprobaciones.
