#!/usr/bin/env bash
# Verifica che tutti gli strumenti necessari siano presenti e che il daemon
# Docker sia raggiungibile. Non installa nulla: se manca qualcosa, si ferma
# e indica come procurarselo.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

require_cmd docker    "installa Docker Desktop: winget install Docker.DockerDesktop"
require_cmd kind      "installa kind: winget install Kubernetes.kind"
require_cmd kubectl   "installa kubectl (incluso in Docker Desktop, oppure: winget install Kubernetes.kubectl)"
require_cmd helm      "installa Helm: winget install Helm.Helm"
require_cmd helmfile  "installa helmfile: nessun pacchetto winget/choco elevabile senza privilegi admin è garantito; scarica il binario da https://github.com/helmfile/helmfile/releases (asset *_windows_amd64.tar.gz) e mettilo in una cartella nel PATH"
require_cmd jq        "installa jq: winget install jqlang.jq"
require_cmd openssl   "installa OpenSSL (incluso in Git for Windows / Git Bash)"
require_cmd curl      "installa curl (incluso in Windows 10+ e Git Bash)"

if ! docker info >/dev/null 2>&1; then
  error "il daemon Docker non risponde. Avvia Docker Desktop e riprova."
  exit 1
fi

# Le email di sistema (invito utente, verifica email, reset password) vanno
# al relay Resend in ogni ambiente - nessun mail-catcher locale di riserva,
# vedi docs/adr/0007-resend-only-email-delivery.md. Controllato qui, non solo
# nell'hook postsync di Helmfile, per fallire prima di spendere minuti su
# cluster/provisioning se la chiave manca.
if [ -z "${RESEND_API_KEY:-}" ]; then
  error "RESEND_API_KEY non impostata: obbligatoria per configurare l'invio email di Keycloak (vedi README.md)."
  exit 1
fi

log "tutti i prerequisiti sono soddisfatti."
