#!/usr/bin/env bash
# Provisiona il catalogo permessi/ruoli del dominio contenuti
# (one-piece-api/docs/user-flows/authentication-and-user-management.md §2.2,
# §7.1/§7.7) sullo stesso registro dinamico già usato per users:*/roles:*/
# audit:* (ADR-0007/0012 di one-piece-user-service) - nessun edit a
# realm-onepiece.json, stessa identica azione che si farebbe a mano dalla
# schermata "Ruoli & permessi", solo automatizzata così ogni ambiente
# (locale, ci, remote) parte già pronto invece di richiedere un passaggio
# manuale prima di poter provare/testare l'area Contenuti. Stesso pattern
# (idempotente, kcadm via "kubectl exec") di
# configure-role-catalog-permissions.sh, agganciato subito dopo come hook
# postsync della release "keycloak".
#
# Crea, se mancanti: i 4 permessi content:read/write/review/publish sul
# client onepiece-proxy, il ruolo realm PUBLISHER; assegna a EDITOR
# content:read+content:write, a REVIEWER content:read+content:review, a
# PUBLISHER content:read+content:publish - il mapping di default del
# documento dei flussi. Non assegna il ruolo PUBLISHER (né EDITOR/REVIEWER)
# a nessun utente: chi lo detiene resta una decisione presa dall'app
# (invito/gestione ruoli), non da questo script.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Placeholder locale (KC_BOOTSTRAP_ADMIN_PASSWORD in keycloak/values-keycloakx.yaml),
# non un segreto reale - stesso pattern di configure-role-catalog-permissions.sh.
kc_admin_password="admin-change-me-locally"

kubectl exec -n auth statefulset/keycloak -- bash -c '
  set -euo pipefail
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password "$1"

  cid=$(/opt/keycloak/bin/kcadm.sh get clients -r onepiece -q clientId=onepiece-proxy --fields id --format csv --noquotes | tail -n1)
  existing_perms=$(/opt/keycloak/bin/kcadm.sh get "clients/$cid/roles" -r onepiece --fields name --format csv --noquotes)

  ensure_permission() {
    if ! printf "%s\n" "$existing_perms" | grep -qx "$1"; then
      /opt/keycloak/bin/kcadm.sh create "clients/$cid/roles" -r onepiece -s "name=$1" -s "description=$2"
    fi
  }
  ensure_permission "content:read" "View the encyclopedia (reviewed, published, retired content)"
  ensure_permission "content:write" "Create/edit an own draft, submit for review, withdraw, delete a never-published draft"
  ensure_permission "content:review" "Claim/release a review, approve or reject a claimed one"
  ensure_permission "content:publish" "Publish a reviewed candidate, roll back, retire, view version history"

  existing_roles=$(/opt/keycloak/bin/kcadm.sh get roles -r onepiece --fields name --format csv --noquotes)
  if ! printf "%s\n" "$existing_roles" | grep -qx "PUBLISHER"; then
    /opt/keycloak/bin/kcadm.sh create roles -r onepiece -s name=PUBLISHER -s "description=Publishes reviewed content, rolls back, retires"
  fi

  grant() {
    local role="$1" perm="$2"
    local held
    held=$(/opt/keycloak/bin/kcadm.sh get-roles -r onepiece --rname "$role" --cclientid onepiece-proxy --fields name --format csv --noquotes)
    if ! printf "%s\n" "$held" | grep -qx "$perm"; then
      /opt/keycloak/bin/kcadm.sh add-roles -r onepiece --rname "$role" --cclientid onepiece-proxy --rolename "$perm"
    fi
  }
  grant EDITOR content:read
  grant EDITOR content:write
  grant REVIEWER content:read
  grant REVIEWER content:review
  grant PUBLISHER content:read
  grant PUBLISHER content:publish
' -- "$kc_admin_password"

echo "[configure-content-permissions] fatto: permessi content:* e ruolo PUBLISHER provisionati."
