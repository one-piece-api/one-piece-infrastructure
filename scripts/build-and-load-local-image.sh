#!/usr/bin/env bash
# Presync hook delle release "user-service" e "user-frontend" in
# helmfile.yaml.gotmpl: nell'ambiente locale ("default") le immagini
# ":local" vivono solo nel Docker daemon dell'host, mai nel containerd
# interno al nodo kind. Senza questo passaggio il Deployment resta in
# ImagePullBackOff finché il --wait di Helm non va in timeout (ADR-0003).
#
# A differenza di scripts/deploy-local.sh (nei repo applicativi, che fa
# anche "kubectl rollout restart"), qui ci si ferma a build + kind load:
# il Deployment non esiste ancora al primo bootstrap, un rollout restart
# fallirebbe. Sarà "helm upgrade --install", subito dopo questo hook, a
# crearlo per la prima volta con l'immagine già disponibile nel nodo.
#
# Nell'ambiente "ci" le immagini vengono invece da GHCR (ADR-0004): qui
# non c'è nulla da fare, il segnale è HELMFILE_ENVIRONMENT != "default".

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

log() { echo "[build-and-load-local-image] $*"; }

if [ "${HELMFILE_ENVIRONMENT:-default}" != "default" ]; then
  log "HELMFILE_ENVIRONMENT=${HELMFILE_ENVIRONMENT}, salto (immagini da registry)."
  exit 0
fi

app_name="${1:?uso: $0 <nome-app, es. one-piece-user-frontend>}"
sibling_dir="../$app_name"
cluster_name="onepiece"

if [ ! -d "$sibling_dir" ]; then
  log "ATTENZIONE: $sibling_dir non trovato accanto a questo repo, salto."
  log "L'immagine ${app_name}:local deve già essere caricata nel cluster kind, altrimenti il deploy fallirà."
  exit 0
fi

if docker image inspect "${app_name}:local" >/dev/null 2>&1; then
  log "${app_name}:local già presente nel Docker daemon locale, salto il build."
else
  log "${app_name}:local non trovata, la costruisco ($sibling_dir/scripts/build-image.sh)..."
  "$sibling_dir/scripts/build-image.sh"
fi

# Sempre eseguito, anche a immagine invariata: veloce (pochi secondi) e
# rende il sync resiliente a un cluster kind che ha perso l'immagine
# (es. dopo un riavvio di Docker Desktop), non solo al primo bootstrap.
log "carico ${app_name}:local nel cluster kind '${cluster_name}'..."
kind load docker-image "${app_name}:local" --name "$cluster_name"
