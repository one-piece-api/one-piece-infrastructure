#!/usr/bin/env bash
# Provisiona il catalogo permessi/ruoli del dominio contenuti
# (one-piece-api/docs/user-flows/content-editorial-workflow.md §2.2)
# sullo stesso registro dinamico già usato per users:*/roles:*/
# audit:* (ADR-0007/0012 di one-piece-user-service) - nessun edit a
# realm-onepiece.json, stessa identica azione che si farebbe a mano dalla
# schermata "Ruoli & permessi", solo automatizzata così ogni ambiente
# (locale, ci, remote) parte già pronto invece di richiedere un passaggio
# manuale prima di poter provare/testare l'area Contenuti. Stesso pattern
# (idempotente, kcadm via "kubectl exec") di
# configure-role-catalog-permissions.sh, agganciato subito dopo come hook
# postsync della release "keycloak".
#
# Crea, se mancanti, e riallinea la descrizione di: content:read, content:write,
# content:review, content:publish, content:retire, content:admin e
# languages:manage sul client onepiece-proxy; crea il ruolo realm PUBLISHER.
# Applica il mapping di default del documento dei flussi:
#   EDITOR    content:read, content:write
#   REVIEWER  content:read, content:review
#   PUBLISHER content:read, content:publish, content:retire
#   ADMIN     tutti i content:*, content:admin incluso, e languages:manage
# Aggiunge soltanto: un permesso tolto a mano da un ruolo dalla schermata
# "Ruoli & permessi" viene riassegnato al deploy successivo, uno aggiunto a
# mano resta. Non assegna ruoli a nessun utente: chi li detiene resta una
# decisione presa dall'app (invito/gestione ruoli) - gli account di prova
# sono in seed-content-qa-users.sh.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Placeholder locale (KC_BOOTSTRAP_ADMIN_PASSWORD in keycloak/values-keycloakx.yaml),
# non un segreto reale - stesso pattern di configure-role-catalog-permissions.sh.
kc_admin_password="admin-change-me-locally"

kubectl exec -n auth statefulset/keycloak -- bash -c '
  set -euo pipefail
  kcadm=/opt/keycloak/bin/kcadm.sh
  $kcadm config credentials --server http://localhost:8080 --realm master --user admin --password "$1"

  cid=$($kcadm get clients -r onepiece -q clientId=onepiece-proxy --fields id --format csv --noquotes | tail -n1)
  existing_perms=$($kcadm get "clients/$cid/roles" -r onepiece --fields name --format csv --noquotes)

  # Crea il permesso se manca; la descrizione viene sempre riallineata, così un
  # cambio di significato (come il passaggio al modello a versioni) arriva anche
  # su un realm già provisionato.
  ensure_permission() {
    if ! printf "%s\n" "$existing_perms" | grep -qx "$1"; then
      $kcadm create "clients/$cid/roles" -r onepiece -s "name=$1" -s "description=$2"
    else
      $kcadm update "clients/$cid/roles/$1" -r onepiece -s "description=$2"
    fi
  }
  ensure_permission "content:read" "Browse content and version history, limited to the statuses visible to the caller"
  ensure_permission "content:write" "See drafts, rejected and in-review versions; open a new version; edit, submit, pull back and delete an own draft"
  ensure_permission "content:review" "See in-review versions; claim, release, approve or reject - never an own version"
  ensure_permission "content:publish" "Publish, archive, recover from archive, restore an older version"
  ensure_permission "content:retire" "Retire the published version"
  ensure_permission "content:admin" "Override ownership, claims and the self-review ban; grants no action by itself"
  ensure_permission "languages:manage" "Manage the language catalog (add/remove supported languages)"

  existing_roles=$($kcadm get roles -r onepiece --fields name --format csv --noquotes)
  if ! printf "%s\n" "$existing_roles" | grep -qx "PUBLISHER"; then
    $kcadm create roles -r onepiece -s name=PUBLISHER -s "description=Publishes, archives, retires and restores content"
  fi

  grant() {
    local role="$1" perm held
    held=$($kcadm get-roles -r onepiece --rname "$role" --cclientid onepiece-proxy --fields name --format csv --noquotes)
    shift
    for perm in "$@"; do
      if ! printf "%s\n" "$held" | grep -qx "$perm"; then
        $kcadm add-roles -r onepiece --rname "$role" --cclientid onepiece-proxy --rolename "$perm"
      fi
    done
  }
  grant EDITOR content:read content:write
  grant REVIEWER content:read content:review
  grant PUBLISHER content:read content:publish content:retire
  grant ADMIN content:read content:write content:review content:publish content:retire content:admin languages:manage
' -- "$kc_admin_password"

echo "[configure-content-permissions] fatto: permessi content:*/languages:manage e ruolo PUBLISHER provisionati."
