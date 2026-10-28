#!/bin/sh
# Dump logico dell'istanza PostgreSQL condivisa (ADR-0027, PR6 D5).
# Uso: pg-backup.sh <cartella-di-uscita> <database>...
# Crea <cartella-di-uscita>/pg-<UTC>.tgz con globals.sql (ruoli) e un
# <database>.dump (pg_dump -Fc) per database: lo stesso formato del
# salvataggio del 2026-10-28, ripristinato con la stessa procedura.
# Connessione dalle variabili libpq (PGHOST, PGUSER, PGPASSWORD).
# Lo eseguono il CronJob dei backup e scripts/07-backup-restore-test.sh.
set -eu

out="$1"
shift
[ "$#" -gt 0 ] || { echo "pg-backup: nessun database indicato" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pg_dumpall --globals-only --file="$work/globals.sql"
for database in "$@"; do
  pg_dump --format=custom --dbname="$database" --file="$work/$database.dump"
done

archive="$out/pg-$(date -u +%Y%m%dT%H%M%SZ).tgz"
tar -czf "$archive" -C "$work" .
echo "$archive"
