#!/usr/bin/env bash
# Prova di ripristino del backup (ADR-0027, PR6 D5): esegue lo stesso script
# del CronJob (helm/charts/postgresql/files/pg-backup.sh) nel pod PostgreSQL,
# stessa immagine, poi ripristina ogni dump in un database temporaneo e
# confronta il numero di righe di ogni tabella con l'originale. Il
# caricamento su Object Storage (rclone, instance principal) non si prova
# qui: senza OCI, si verifica al primo backup sul remoto.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$REPO_ROOT"

# Git Bash (Windows) converte gli argomenti "/tmp/..." in percorsi C:/...
# prima di passarli a kubectl exec: qui sono percorsi dentro il pod.
export MSYS_NO_PATHCONV=1

POD="one-piece-postgresql-0"
DATA_NAMESPACE="data"
DATABASES=(keycloak user_service content_service)
ROLES=(keycloak user_service content_service public_api_reader)
BACKUP_SCRIPT="helm/charts/postgresql/files/pg-backup.sh"
WORK_DIR="/tmp/backup-restore-test"
RESTORE_SUFFIX="_restore_test"

# Righe per tabella ("schema.tabella=n"), in ordine: conteggi esatti, non le
# stime delle statistiche.
COUNT_ROWS_SQL="SELECT coalesce(string_agg(format('%s.%s=%s', table_schema, table_name,
  (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM %I.%I',
  table_schema, table_name), false, true, '')))[1]::text), ' ' ORDER BY table_schema, table_name), '')
  FROM information_schema.tables
  WHERE table_type = 'BASE TABLE' AND table_schema NOT IN ('pg_catalog', 'information_schema')"

in_pod() {
  kubectl exec -n "$DATA_NAMESPACE" "$POD" -- "$@"
}

# psql_in <database> <sql>
psql_in() {
  in_pod psql -U postgres -d "$1" -AtXc "$2"
}

cleanup() {
  for database in "${DATABASES[@]}"; do
    in_pod dropdb -U postgres --if-exists "$database$RESTORE_SUFFIX" >/dev/null 2>&1 || true
  done
  in_pod rm -rf "$WORK_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

failures=0
fail() { error "$*"; failures=$((failures + 1)); }

cleanup
in_pod mkdir -p "$WORK_DIR/out" "$WORK_DIR/extract"

log "1/3 backup con lo script del CronJob..."
archive="$(kubectl exec -i -n "$DATA_NAMESPACE" "$POD" -- \
  env PGUSER=postgres sh -s -- "$WORK_DIR/out" "${DATABASES[@]}" <"$BACKUP_SCRIPT" | tail -n 1)"
log "archivio: $archive"
in_pod tar -xzf "$archive" -C "$WORK_DIR/extract"

log "2/3 globals.sql contiene i ruoli dei servizi..."
for role in "${ROLES[@]}"; do
  in_pod grep -q "^CREATE ROLE $role;" "$WORK_DIR/extract/globals.sql" \
    || fail "ruolo $role assente da globals.sql"
done

log "3/3 ripristino di ogni database e confronto delle righe..."
for database in "${DATABASES[@]}"; do
  restored="$database$RESTORE_SUFFIX"
  in_pod createdb -U postgres "$restored"
  if ! in_pod pg_restore -U postgres --exit-on-error -d "$restored" "$WORK_DIR/extract/$database.dump"; then
    fail "pg_restore di $database fallito"
    continue
  fi
  original_rows="$(psql_in "$database" "$COUNT_ROWS_SQL")"
  restored_rows="$(psql_in "$restored" "$COUNT_ROWS_SQL")"
  [ -n "$original_rows" ] || fail "$database: nessuna tabella"
  [ "$original_rows" = "$restored_rows" ] \
    || fail "$database: righe diverse dopo il ripristino ($original_rows / $restored_rows)"
done

[ "$failures" -eq 0 ] || { error "$failures verifiche fallite"; exit 1; }
log "backup ripristinato senza differenze."
