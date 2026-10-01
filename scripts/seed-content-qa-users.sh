#!/usr/bin/env bash
# Account di prova per collaudare il workflow editoriale dei contenuti
# (one-piece-api/docs/implementation-plan-content.md, Step 0). Gli utenti di
# realm-onepiece.json coprono ADMIN (luffy), un solo EDITOR attivo (nami) e un
# REVIEWER (zoro): per provare le regole che richiedono identità distinte
# servono anche
#   chopper  EDITOR             un secondo autore (bozze altrui in sola lettura)
#   vivi     PUBLISHER          pubblica senza poter scrivere né revisionare
#   law      EDITOR + REVIEWER  divieto di revisionare un proprio contenuto
#
# Creati qui e non in realm-onepiece.json perché PUBLISHER non è un ruolo del
# realm dichiarativo: lo crea configure-content-permissions.sh, che gira subito
# prima come hook postsync della release "keycloak".
#
# Solo in "default" (locale) e "ci": password note e committate non devono
# arrivare su un ambiente raggiungibile da Internet. Idempotente: un utente
# già presente non viene toccato (nemmeno la password), i ruoli mancanti
# vengono aggiunti.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ "${HELMFILE_ENVIRONMENT:-default}" = "remote" ]; then
  echo "[seed-content-qa-users] HELMFILE_ENVIRONMENT=remote, salto (nessun account con password nota fuori da locale/ci)."
  exit 0
fi

# Placeholder locale (KC_BOOTSTRAP_ADMIN_PASSWORD in keycloak/values-keycloakx.yaml),
# non un segreto reale - stesso pattern di configure-content-permissions.sh.
kc_admin_password="admin-change-me-locally"

kubectl exec -n auth statefulset/keycloak -- bash -c '
  set -euo pipefail
  kcadm=/opt/keycloak/bin/kcadm.sh
  $kcadm config credentials --server http://localhost:8080 --realm master --user admin --password "$1"

  # Stessa convenzione degli utenti di realm-onepiece.json: email
  # <username>@onepiece.local, password <username>-change-me.
  seed_user() {
    local username="$1" first_name="$2" last_name="$3" role existing
    shift 3
    existing=$($kcadm get users -r onepiece -q "username=$username" -q exact=true --fields username --format csv --noquotes)
    if [ -z "$existing" ]; then
      $kcadm create users -r onepiece -s "username=$username" -s "email=$username@onepiece.local" \
        -s "firstName=$first_name" -s "lastName=$last_name" -s enabled=true -s emailVerified=true
      $kcadm set-password -r onepiece --username "$username" --new-password "$username-change-me"
    fi
    for role in "$@"; do
      $kcadm add-roles -r onepiece --uusername "$username" --rolename "$role"
    done
  }
  seed_user chopper "Tony Tony" "Chopper" EDITOR
  seed_user vivi "Nefertari" "Vivi" PUBLISHER
  seed_user law "Trafalgar" "Law" EDITOR REVIEWER
' -- "$kc_admin_password"

echo "[seed-content-qa-users] fatto: account di prova chopper (EDITOR), vivi (PUBLISHER), law (EDITOR+REVIEWER)."
