#!/usr/bin/env bash
# Verifica i ruoli creati dal Job di bootstrap dell'istanza PostgreSQL
# condivisa: ogni proprietario si collega solo al proprio database
# (ADR-0016), il lettore dell'API pubblica solo a content_service, con i suoi
# limiti (ADR-0018). Non verifica i permessi sullo schema "published": li
# concede una migrazione di content-service, testata in quel repository.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$REPO_ROOT"

POD="one-piece-postgresql-0"
DATA_NAMESPACE="data"

# as_superuser <sql>
as_superuser() {
  kubectl exec -n "$DATA_NAMESPACE" "$POD" -- psql -U postgres -AtXc "$1"
}

# can_connect <ruolo> <database>: 0 se il ruolo ha CONNECT sul database.
can_connect() {
  [ "$(as_superuser "SELECT has_database_privilege('$1', '$2', 'CONNECT')")" = "t" ]
}

failures=0
fail() { error "$*"; failures=$((failures + 1)); }

log "1/3 ogni proprietario si collega solo al proprio database..."
for owner in keycloak user_service content_service; do
  for database in keycloak user_service content_service; do
    if [ "$owner" = "$database" ]; then
      can_connect "$owner" "$database" || fail "$owner non si collega a $database"
    else
      ! can_connect "$owner" "$database" || fail "$owner si collega a $database"
    fi
  done
done

log "2/3 public_api_reader si collega solo a content_service..."
for database in keycloak user_service content_service; do
  if [ "$database" = "content_service" ]; then
    can_connect public_api_reader "$database" || fail "public_api_reader non si collega a $database"
  else
    ! can_connect public_api_reader "$database" || fail "public_api_reader si collega a $database"
  fi
done

log "3/3 public_api_reader ha i suoi limiti e nessun privilegio amministrativo..."
reader="$(as_superuser "SELECT rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolconnlimit,
  array_to_string(rolconfig, ',') FROM pg_roles WHERE rolname = 'public_api_reader'")"
expected="t|f|f|f|10|statement_timeout=2s,default_transaction_read_only=on"
[ "$reader" = "$expected" ] || fail "public_api_reader inatteso: '$reader' (atteso '$expected')"

[ "$failures" -eq 0 ] || { error "$failures verifiche fallite"; exit 1; }
log "ruoli del database verificati."
