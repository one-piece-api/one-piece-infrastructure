#!/usr/bin/env bash
# Genera e applica la ConfigMap del realm da keycloak/realm-onepiece.json.
#
# Hook presync della release "keycloak" in helmfile.yaml: gira prima di ogni
# sync così la ConfigMap è sempre allineata al realm prima che Keycloak la
# monti, senza mantenere una copia YAML duplicata potenzialmente
# disallineata — realm-onepiece.json resta l'unica source of truth (vedi
# docs/adr/0001-local-auth-stack.md).
#
# Attenzione: questo da solo NON basta a propagare modifiche a un realm che
# esiste già nel DB. "--import-realm" (comando di avvio di Keycloak, vedi
# keycloak/values-keycloakx.yaml) crea entità mancanti ma non aggiorna quelle
# già presenti (bug noto: keycloak/keycloak#14884). Non serve più correggerlo
# a mano: l'hook postsync scripts/sync-realm-config.sh (keycloak-config-cli)
# riconcilia il realm con questo stesso file ad ogni sync - vedi
# docs/adr/0011-keycloak-config-cli-realm-sync.md.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

kubectl create configmap one-piece-realm-config \
  --from-file=realm-onepiece.json=keycloak/realm-onepiece.json \
  -n auth --dry-run=client -o yaml | kubectl apply -f -
