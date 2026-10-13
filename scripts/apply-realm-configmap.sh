#!/usr/bin/env bash
# Genera e applica le ConfigMap del realm: keycloak/realm-onepiece.json
# (config) e, fuori da "remote", realm-onepiece-dev-users.json (utenti di prova); in "remote" realm-onepiece-hardening.json.
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

# Fuori da un cluster kind locale, HELMFILE_ENVIRONMENT è obbligatoria: senza,
# una sync manuale verso il remoto applicherebbe il ramo "non remote" e
# importerebbe gli utenti di prova (D2).
if [ -z "${HELMFILE_ENVIRONMENT:-}" ] && [[ "$(kubectl config current-context)" != kind-* ]]; then
  echo "HELMFILE_ENVIRONMENT non impostata con un contesto non-kind: esportala (es. remote)." >&2
  exit 1
fi

kubectl create configmap one-piece-realm-config \
  --from-file=realm-onepiece.json=keycloak/realm-onepiece.json \
  -n auth --dry-run=client -o yaml | kubectl apply -f -

# Utenti di prova (D2, piano production-remote): in una ConfigMap a parte,
# montata solo dal Job di keycloak-config-cli e mai da Keycloak (--import-realm
# scarterebbe comunque un secondo file sullo stesso realm). In "remote" non
# esiste: se c'era da un deploy precedente va tolta, non solo non aggiornata.
if [ "${HELMFILE_ENVIRONMENT:-default}" = "remote" ]; then
  kubectl delete configmap one-piece-realm-dev-users -n auth --ignore-not-found
else
  kubectl create configmap one-piece-realm-dev-users \
    --from-file=realm-onepiece-dev-users.json=keycloak/realm-onepiece-dev-users.json \
    -n auth --dry-run=client -o yaml | kubectl apply -f -
fi

# Irrigidimento di produzione (D4): soglia brute-force e password policy
# sovrascrivono i valori permissivi del realm base. Solo in "remote": altrove i
# test e le password di prova non rispetterebbero la policy.
if [ "${HELMFILE_ENVIRONMENT:-default}" = "remote" ]; then
  kubectl create configmap one-piece-realm-hardening \
    --from-file=realm-onepiece-hardening.json=keycloak/realm-onepiece-hardening.json \
    -n auth --dry-run=client -o yaml | kubectl apply -f -
else
  kubectl delete configmap one-piece-realm-hardening -n auth --ignore-not-found
fi
