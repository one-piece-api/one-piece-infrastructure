#!/usr/bin/env bash
# Crea l'intero ambiente locale di autenticazione da zero, un solo comando:
# prerequisiti → cluster kind → stack (namespace, PostgreSQL, Keycloak,
# whoami, oauth2-proxy, orchestrati da Helmfile) → smoke test end-to-end.
#
# Le dipendenze tra i componenti dello stack sono dichiarate in
# ../helmfile.yaml (needs:), non nell'ordine di questo script — vedi
# docs/adr/0002-helmfile-orchestration.md.
#
# HELMFILE_ENVIRONMENT sceglie tra "default" (locale, immagini "kind load
# docker-image") e "ci" (immagini da GHCR) — vedi environments: in
# ../helmfile.yaml.gotmpl e docs/adr/0004-ci-images-from-ghcr.md. Non
# impostata, vale "default": il comportamento locale resta invariato.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib/common.sh

export HELMFILE_ENVIRONMENT="${HELMFILE_ENVIRONMENT:-default}"

./00-check-prerequisites.sh
./01-create-cluster.sh

log "sincronizzo lo stack (namespace, PostgreSQL, Keycloak, whoami, oauth2-proxy) via Helmfile [ambiente: $HELMFILE_ENVIRONMENT]..."
(cd "$REPO_ROOT" && helmfile --environment "$HELMFILE_ENVIRONMENT" sync)

./02-smoke-test.sh

cat <<'EOF'

Ambiente pronto. Per accedervi:

  kubectl port-forward svc/keycloak-http -n auth 8080:8080 &
  kubectl port-forward svc/oauth2-proxy  -n auth 4180:4180 &
  # poi apri http://localhost:4180

Promemoria:
  - Le credenziali placeholder (admin Keycloak, DB, client secret) vanno
    sostituite prima di qualunque ambiente non locale.
  - oauth2-proxy/secret.local.yaml contiene un cookie secret generato
    casualmente: non è mai committato (vedi .gitignore) e non va riusato
    fuori da questo cluster kind locale.
  - Per aggiornare lo stack dopo una modifica: helmfile sync (dalla root)
  - Per distruggere tutto: scripts/teardown.sh
EOF
