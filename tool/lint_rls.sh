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

  section "Flag de borrado remoto coherente con las RPCs versionadas (S-8)"
  FLAG_ON=$(grep -Eo "familyMemberRemoteDeletionEnabled[[:space:]]*=[[:space:]]*(true|false)" \
      "$REPO_ROOT/lib/services/family_member_deletion_service.dart" | grep -c "true" || true)
  if [ "$FLAG_ON" -gt 0 ]; then
    for fn in prepare_family_member_delete finish_family_member_delete; do
      if grep -qE "create or replace function public\.${fn}\(" "$REPO_ROOT"/supabase/migrations/*.sql \
          && grep -qE "revoke all on function public\.${fn}\(uuid\) from public, anon" "$REPO_ROOT"/supabase/migrations/*.sql \
          && grep -qE "grant execute on function public\.${fn}\(uuid\) to authenticated" "$REPO_ROOT"/supabase/migrations/*.sql; then
        pass "${fn} versionada con sus revokes/grants"
      else
        fail "Flag=true pero falta ${fn} (con revoke/grant) en migrations/ (S-8)"
      fi
    done
  else
    pass "Flag de borrado remoto apagado: sin gate que comprobar"
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

  section "Flag de borrado remoto vs RPCs reales (S-8)"
  FLAG_ON=$(grep -Eo "familyMemberRemoteDeletionEnabled[[:space:]]*=[[:space:]]*(true|false)" \
      "$REPO_ROOT/lib/services/family_member_deletion_service.dart" | grep -c "true" || true)
  if [ "$FLAG_ON" -gt 0 ]; then
    for fn in prepare_family_member_delete finish_family_member_delete; do
      rows=$(run "select p.proname||' '||coalesce(p.pronacl::text,'-')
                  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='${fn}';")
      if [ -z "$rows" ]; then
        fail "Flag=true pero no existe la funcion ${fn} (S-8)"
      elif printf '%s' "$rows" | grep -q "anon="; then
        fail "${fn} tiene EXECUTE para anon (S-8)"
      elif ! printf '%s' "$rows" | grep -q "authenticated=X"; then
        fail "${fn} sin EXECUTE para authenticated (S-8)"
      else
        pass "${fn} instalada, solo authenticated"
      fi
    done
  else
    pass "Flag de borrado remoto apagado: sin gate que comprobar"
  fi
fi

# -----------------------------------------------------------------------------
# S-17: ninguna politica se reescribe de forma dinamica. format('alter policy')
# barria pg_policy y alteraba politicas ajenas sin lista blanca ni registro.
# Aplica a ambos modos (comprueba los .sql del repo, no la BD).
# -----------------------------------------------------------------------------
section "Reescritura dinamica de politicas ajenas (S-17)"
HITS=$(grep -rniE "format[[:space:]]*\(.{0,60}alter[[:space:]]+policy" "$REPO_ROOT/supabase" --include='*.sql' 2>/dev/null \
    | sed -E 's/^[^:]*:[0-9]+:[[:space:]]*--.*$//' | grep -v '^[[:space:]]*$' || true)
if [ -n "$HITS" ]; then
  printf '%s\n' "$HITS" | sed 's/^/      /'
  fail "format('alter policy ...'): usa ALTER explicitos por politica (S-17)"
else
  pass "Sin alter policy dinamico en supabase/"
fi

# -----------------------------------------------------------------------------
# S-19: can_edit en get_story_photo_metadata debe calcularse con el mismo
# predicado que set_story_photo (owner o recorded_by), no con un literal
# true. Solo se comprueban las migraciones versionadas: supabase/manual/04 es
# un script historico instalado que se conserva tal cual (decision registrada).
# -----------------------------------------------------------------------------
section "can_edit calculado en get_story_photo_metadata (S-19)"
HITS=$(grep -rniE "'can_edit'[[:space:]]*,[[:space:]]*true" "$REPO_ROOT/supabase/migrations" --include='*.sql' 2>/dev/null \
    | sed -E 's/^[^:]*:[0-9]+:[[:space:]]*--.*$//' | grep -v '^[[:space:]]*$' || true)
if [ -n "$HITS" ]; then
  printf '%s\n' "$HITS" | sed 's/^/      /'
  fail "'can_edit' literal true: usa el predicado owner/recorder (S-19)"
else
  pass "can_edit calculado (sin literal true) en migrations/"
fi

# -----------------------------------------------------------------------------
# S-27: profiles y family_members tienen columna updated_at y deben mantener
# su trigger; family_invitations ya lo tiene desde el baseline (0004).
# -----------------------------------------------------------------------------
section "Trigger de updated_at en profiles y family_members (S-27)"
for t in profiles family_members; do
  if grep -qE "create trigger ${t}_set_updated_at" "$REPO_ROOT/supabase/migrations"/*.sql 2>/dev/null; then
    pass "${t}_set_updated_at presente en migrations/"
  else
    fail "Falta trigger ${t}_set_updated_at en migrations/ (S-27)"
  fi
done

# -----------------------------------------------------------------------------
# S-28: get_family_invitation_preview es una lectura; no puede tomar locks
# (FOR UPDATE). Los FOR UPDATE de rutas de escritura (accept, set_story_photo,
# prepare/finish...) son legitimos y quedan fuera de esta comprobacion.
# -----------------------------------------------------------------------------
section "Preview de invitacion sin FOR UPDATE (S-28)"
PREVIEW_BODY=$(awk '
  /^create or replace function public\.get_family_invitation_preview\(/ { in_fn=1 }
  in_fn { print }
  in_fn && /^\$function\$;/ { exit }
' "$REPO_ROOT"/supabase/migrations/*.sql)
if [ -z "$PREVIEW_BODY" ]; then
  fail "get_family_invitation_preview no encontrada en migrations/ (S-28)"
elif printf '%s\n' "$PREVIEW_BODY" | sed -E 's/^[[:space:]]*--.*$//' | grep -qiE "for[[:space:]]+update"; then
  fail "get_family_invitation_preview usa FOR UPDATE en una lectura (S-28)"
else
  pass "get_family_invitation_preview presente y sin FOR UPDATE"
fi

# -----------------------------------------------------------------------------
# S-29: el bucket avatars necesita su politica DELETE own-folder (habilita la
# retencion cuando la app implemente el borrado; ver 20261115000001).
# -----------------------------------------------------------------------------
section "Politica DELETE propia en el bucket avatars (S-29)"
if grep -qE 'create policy "Users can delete their own avatar"' "$REPO_ROOT/supabase/migrations"/*.sql 2>/dev/null; then
  pass "Politica de DELETE own-folder en avatars presente en migrations/"
else
  fail "Falta la politica DELETE own-folder de avatars en migrations/ (S-29)"
fi

# -----------------------------------------------------------------------------
# S-30: la politica muerta "Inviters can view their own invitations" debe
# quedar eliminada por una migracion versionada (jamas se evaluo; 0005 no da
# grants sobre family_invitations a authenticated).
# La baseline 0002 contiene drop+create (patron if exists); por eso se
# comprueba que la ULTIMA aparicion en orden de migracion sea un drop y no un
# create: si alguien vuelve a crearla al final, el gate falla.
# -----------------------------------------------------------------------------
section "Politica muerta de family_invitations eliminada (S-30)"
LAST_STMT=$(grep -hE '(create|drop) policy.*"Inviters can view their own invitations"' \
  "$REPO_ROOT"/supabase/migrations/*.sql 2>/dev/null | tail -n 1 || true)
if [ -z "$LAST_STMT" ]; then
  fail "Ninguna referencia a la politica muerta en migrations/ (S-30)"
elif printf '%s' "$LAST_STMT" | grep -qE '^[[:space:]]*drop policy'; then
  pass "Ultima aparicion de la politica en migrations/ es un DROP"
else
  printf '%s\n' "$LAST_STMT" | sed 's/^/      /'
  fail "La politica muerta se recrea tras el drop (la ultima aparicion es un CREATE) (S-30)"
fi

# -----------------------------------------------------------------------------
# C-4: las politicas de storage no pueden comparar ids en texto contra
# storage.foldername (derrota family_members_pkey / question_requests_pkey y
# reevalua foldername). Fix: helpers family_member_photo_allowed /
# response_audio_allowed en 0003, con cast a uuid guardado por regex.
# Solo se examina Codigo (los comentarios -- se ignoran) y solo migrations/
# (manual/ es historico y queda exento por decision).
# -----------------------------------------------------------------------------
section "Politicas de storage sin casts de id a texto (C-4)"
C4_HITS=$(awk '{
  line = $0
  sub(/--.*/, "", line)
  if (line ~ /\.id\)?::text[[:space:]]*=[[:space:]]*\(?(storage\.)?foldername/)
    print FILENAME ":" FNR
}' "$REPO_ROOT"/supabase/migrations/*.sql 2>/dev/null)
if [ -n "$C4_HITS" ]; then
  printf '%s\n' "$C4_HITS" | sed 's/^/      /'
  fail "Comparacion id::text = storage.foldername en migrations/ (C-4)"
else
  pass "Sin casts de id a texto contra storage.foldername en migrations/"
fi

printf '\n'
if [ "$FAILURES" -gt 0 ]; then
  printf 'LINT FALLIDO: %d problema(s).\n' "$FAILURES"
  exit 1
fi
printf 'LINT OK: sin problemas.\n'
