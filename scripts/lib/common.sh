#!/usr/bin/env bash
# Costanti e helper condivisi da tutti gli script in scripts/.
# Va incluso con "source", non eseguito direttamente.

set -euo pipefail

CLUSTER_NAME="onepiece"
NAMESPACE="auth"

# Radice del repository, calcolata relativamente a questo file: gli script
# funzionano indipendentemente dalla directory da cui vengono lanciati.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log()   { echo "[$(basename "$0")] $*"; }
warn()  { echo "[$(basename "$0")] ATTENZIONE: $*" >&2; }
error() { echo "[$(basename "$0")] ERRORE: $*" >&2; }

# require_cmd <comando> <suggerimento-installazione>
# Verifica che un comando sia in PATH, altrimenti esce con un messaggio
# chiaro su come procurarselo (mai installato automaticamente).
require_cmd() {
  local cmd="$1" hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "comando '$cmd' non trovato. $hint"
    exit 1
  fi
}
