#!/usr/bin/env bash
# =============================================================================
# tool/lint_rls.sh
# Lint de seguridad para el esquema SQL del proyecto. Falla (exit 1) si
# detecta cualquiera de las condiciones prohibidas.
#
# Uso:
#   ./tool/lint_rls.sh                 # comprueba el estado real via psql
#   ./tool/lint_rls.sh --files         # solo inspecciona los .sql del repo
#
# Requiere para --files: grep. Para el modo psql: PGBASE/PGHOST/... o
# SUPABASE_DB_URL como variable de entorno.
# =============================================================================
set -euo pipefail

MODE="psql"
[ "${1:-}" = "--files" ] && MODE="files"

FAILURES=0
fail() { printf '  ✗ %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf '  ✓ %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Roles que pueden recibir DML en tablas de public. TRUNCATE/REFERENCES/
# TRIGGER se tratan aparte.
ALLOWED_DML_ROLES="authenticated|postgres"

if [ "$MODE" = "files" ]; then
  # -------------------------------------------------------------------------
  # Modo estático: inspecciona los ficheros .sql del repositorio.
  #
  # IMPORTANTE: los ficheros 0001..0006 son BASELINE y reproducen a proposito
  # el estado actual del proyecto (incluidos los grant truncate que 0007
  # revoca). Se excluyen de las comprobaciones de "estado deseado" para no
  # generar falsos positivos; solo se exige que 0007 contenga las revocaciones.
  # -------------------------------------------------------------------------
  SQL_FILES=$(find "$REPO_ROOT/supabase" -name '*.sql' ! -name '2026111100000[1-6]_*')
  # Lineas de comentario eliminadas antes de cualquier grep.
  strip_comments() { sed -E 's/^[[:space:]]*--.*$//'; }

  section "Politicas con using/with_check = true"
  HITS=$(grep -rniE "using[[:space:]]*\([[:space:]]*true[[:space:]]*\)|with_check[[:space:]]*\([[:space:]]*true[[:space:]]*\)" \
      $SQL_FILES 2>/dev/null | strip_comments | grep -v '^[[:space:]]*$' || true)
  if [ -n "$HITS" ]; then
    printf '%s\n' "$HITS" | sed 's/^/      /'
    fail "Politica con acceso blanket (using true)"
  else
    pass "Ninguna politica con using/with_check = true"
  fi

  section "ENABLE ROW LEVEL SECURITY en el baseline"
  for t in profiles family_members question_requests stories family_invitations family_member_deletions; do
    if grep -qiE "alter table public\.${t} enable row level security" \
        "$REPO_ROOT/supabase/migrations"/*.sql 2>/dev/null; then
      pass "RLS declarado para ${t}"
    else
      fail "Falta 'enable row level security' para ${t}"
    fi
  done

  section "SECURITY DEFINER con search_path declarado"
  # Toda función SECURITY DEFINER debe fijar search_path.
  while IFS= read -r file; do
    # Extrae bloques de función y comprueba que SECURITY DEFINER va con SET search_path.
    if awk '
      /create or replace function/ { in_fn=1; def=0; sp=0; name=$0 }
      in_fn && /security definer/ { def=1 }
      in_fn && /set search_path/  { sp=1 }
      in_fn && /\$function\$[[:space:]]*;/ {
        if (def && !sp) { print FILENAME": "name; bad=1 }
        in_fn=0
      }
      END { exit bad ? 0 : 1 }
    ' "$file"; then
      fail "SECURITY DEFINER sin SET search_path en: $file"
    fi
  done < <(find "$REPO_ROOT/supabase" -name '*.sql')
  pass "Comprobacion de search_path completada"

  section "Grant TRUNCATE a roles de aplicacion (excluye baseline 0001-0006)"
  HITS=$(grep -rniE "grant[[:space:]]+truncate" $SQL_FILES 2>/dev/null \
      | strip_comments | grep -v '^[[:space:]]*$' || true)
  if [ -n "$HITS" ]; then
    printf '%s\n' "$HITS" | sed 's/^/      /'
    fail "Grant TRUNCATE a anon/authenticated (TRUNCATE no cubierto por RLS)"
  else
    pass "Sin grant TRUNCATE fuera del baseline"
  fi

  section "Revocacion de TRUNCATE presente en 0007 (S-24)"
  if grep -qE "revoke truncate" "$REPO_ROOT/supabase/migrations/20261111000007_hardening.sql"; then
    pass "0007 revoca TRUNCATE"
  else
    fail "0007 no revoca TRUNCATE (S-24)"
  fi

  section "Buckets sin limite de tamano en 0007"
  if grep -qE "file_size_limit" "$REPO_ROOT/supabase/migrations/20261111000007_hardening.sql"; then
    pass "0007 define file_size_limit"
  else
    fail "0007 no define file_size_limit (S-23)"
  fi

else
  # -------------------------------------------------------------------------
  # Modo psql: comprueba el ESTADO REAL de la base de datos.
  # -------------------------------------------------------------------------
  if ! command -v psql >/dev/null 2>&1; then
    echo "psql no encontrado. Usa './tool/lint_rls.sh --files'." >&2
    exit 2
  fi

  # SUPABASE_DB_URL p. ej. postgresql://postgres:pass@db.PROJ.supabase.co:5432/postgres
  URL="${SUPABASE_DB_URL:-${DATABASE_URL:-}}"
  if [ -z "$URL" ]; then
    echo "Define SUPABASE_DB_URL (o DATABASE_URL)." >&2
    exit 2
  fi

  run() { psql "$URL" -X -q -A -t -F$'\t' -c "$1"; }

  section "Politicas con acceso blanket"
  rows=$(run "select schemaname||'.'||tablename||' -> '||policyname
              from pg_policies
              where schemaname in ('public','storage')
                and (qual = 'true' or with_check = 'true');")
  if [ -n "$rows" ]; then
    printf '%s\n' "$rows" | sed 's/^/      /'
    fail "Politica con using/with_check = true"
  else
    pass "Ninguna politica con acceso blanket"
  fi

  section "Tablas public sin RLS"
  rows=$(run "select c.relname from pg_class c
              join pg_namespace n on n.oid = c.relnamespace
              where n.nspname='public' and c.relkind='r' and not c.relrowsecurity;")
  if [ -n "$rows" ]; then
    printf '%s\n' "$rows" | sed 's/^/      /'
    fail "Tabla sin RLS en public"
  else
    pass "Las 6 tablas tienen RLS activo"
  fi

  section "SECURITY DEFINER accesible a anon"
  rows=$(run "select p.proname from pg_proc p
              join pg_namespace n on n.oid = p.pronamespace
              where n.nspname='public' and p.prosecdef
                and p.proacl::text ~ '(anon|authenticated)=X';")
  if [ -n "$rows" ]; then
    printf '%s\n' "$rows" | sed 's/^/      /'
    fail "Funcion SECURITY DEFINER con EXECUTE para anon/authenticated"
  else
    pass "Ninguna SECURITY DEFINER expuesta a anon"
  fi

  section "SECURITY DEFINER sin search_path fijado"
  rows=$(run "select p.proname from pg_proc p
              join pg_namespace n on n.oid = p.pronamespace
              where n.nspname='public' and p.prosecdef
                and not exists (
                  select 1 from pg_proc p2
                  where p2.oid = p.oid
                    and pg_get_functiondef(p2.oid) like '%SET search_path%');")
  if [ -n "$rows" ]; then
    printf '%s\n' "$rows" | sed 's/^/      /'
    fail "SECURITY DEFINER sin SET search_path"
  else
    pass "Todas las SECURITY DEFINER fijan search_path"
  fi

  section "TRUNCATE concedido a anon/authenticated (S-24)"
  rows=$(run "select grantee||' -> '||table_name from information_schema.role_table_grants
              where table_schema='public' and privilege_type='TRUNCATE'
                and grantee in ('anon','authenticated');")
  if [ -n "$rows" ]; then
    printf '%s\n' "$rows" | sed 's/^/      /'
    fail "TRUNCATE concedido a roles de aplicacion"
  else
    pass "TRUNCATE revocado de anon/authenticated"
  fi

  section "Buckets sin limite de tamano (S-23)"
  rows=$(run "select id from storage.buckets
              where id in ('story-audio','avatars','family-member-photos','story-photos')
                and file_size_limit is null;")
  if [ -n "$rows" ]; then
    printf '%s\n' "$rows" | sed 's/^/      /'
    fail "Bucket sin file_size_limit"
  else
    pass "Los 4 buckets tienen file_size_limit"
  fi

  section "question_text sin limite superior (S-25)"
  rows=$(run "select conname from pg_constraint
              where conrelid='public.question_requests'::regclass
                and pg_get_constraintdef(oid) like '%char_length%<= 500%';")
  if [ -n "$rows" ]; then
    pass "Constraint de longitud presente en question_requests"
  else
    fail "Falta constraint de longitud en question_requests"
  fi

  section "Indices criticos presentes (C-3)"
  for idx in question_requests_recipient_status_created_idx \
             question_requests_recipient_status_answered_idx \
             question_requests_sender_id_idx \
             family_members_linked_account_id_idx \
             family_member_deletions_owner_id_idx \
             stories_family_member_created_idx; do
    rows=$(run "select 1 from pg_indexes where indexname='${idx}';")
    if [ -n "$rows" ]; then
      pass "${idx}"
    else
      fail "Falta indice ${idx}"
    fi
  done
fi

printf '\n'
if [ "$FAILURES" -gt 0 ]; then
  printf 'LINT FALLIDO: %d problema(s).\n' "$FAILURES"
  exit 1
fi
printf 'LINT OK: sin problemas.\n'
