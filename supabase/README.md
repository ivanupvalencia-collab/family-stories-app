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
000002_baseline_policies.sql    6 políticas en public + 24 en storage.objects
000003_baseline_functions.sql   26 funciones (incluye las 6 RPC que faltaban)
000004_baseline_triggers.sql    8 triggers de tabla + event trigger rls_auto_enable
000005_baseline_grants.sql      grants por rol + 4 buckets
000006_indexes.sql              A: 16 índices existentes · B: 6 índices nuevos (C-3)
000007_hardening.sql            ⚠️ SÍ cambia estado: S-23, S-24, S-25, S-31
20261112000001_avatar_url_allowlist.sql  ⚠️ SÍ cambia estado: CHECK en profiles.avatar_url (S-5) · NO aplicado
20261113000001_text_limits.sql            ⚠️ SÍ cambia estado: CHECK en family_members.name ≤ 200 (S-13) · NO aplicado
```

**0001–0006 son un no-op** sobre el proyecto vivo: reproducen el estado actual
(`create or replace`, `drop policy if exists`, `create index if not exists`).
**0007 sí modifica el proyecto**: revoca `TRUNCATE`, limita buckets y añade el
límite de `question_text`. **0008 (S-5) añade un `CHECK` a `profiles.avatar_url`
y todavía NO se ha aplicado a producción**: incluye un `select` de pre-chequeo
que debe devolver 0 filas antes del `add constraint`. **0009 (S-13) añade el
`CHECK` de `family_members.name`** (NOT VALID + validate con aviso, igual que
el de `question_text`) y tampoco se ha aplicado.

### Correcciones sobre el volcado crudo

El exportador del dashboard devolvió tres defectos que `0001` corrige:

1. **Orden inválido** — `stories` declaraba FK hacia `question_requests`
   creándolo antes.
2. **Constraint duplicado** — `family_invitations_member_owner_fkey` aparecía
   dos veces, la segunda apuntando a `family_members(owner_id)` que no tiene
   `UNIQUE` (inválido en PostgreSQL). `inviter_id` conserva su FK correcta a
   `auth.users(id)`.
3. **Sin entorno de autorización** — el volcado solo traía `CREATE TABLE`.

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
| S-19 | `get_story_photo_metadata` devuelve `can_edit` siempre `true` | ⏳ documentado en `0003` |
| S-23 | Buckets sin límite de tipo/tamaño | ✅ `0007` |
| S-24 | `TRUNCATE` para `anon`/`authenticated` | ✅ `0007` |
| S-25 | `question_text` sin límite superior | ✅ `0007` |
| S-27 | `updated_at` sin trigger en 4 tablas | ⏳ documentado en `0004` |
| S-28 | `get_family_invitation_preview` hace `FOR UPDATE` en una lectura | ⏳ documentado en `0003` |
| S-29 | Bucket `avatars` sin política `DELETE` | ⏳ abierto |
| S-30 | Política muerta en `family_invitations` | ⏳ documentado en `0002` |
| C-4 | Casts `fm.id::text` bloquean el índice en políticas de storage | ⏳ abierto (requiere prueba en vivo) |

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
