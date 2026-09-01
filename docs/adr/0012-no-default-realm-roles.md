# ADR-0012: Nessun ruolo di default sui nuovi utenti Keycloak

## Contesto

Ogni realm Keycloak crea automaticamente un ruolo composito
`default-roles-<realm>` (qui `default-roles-onepiece`), assegnato a ogni
nuovo utente indipendentemente dal percorso di creazione (Admin Console,
Admin REST API, self-registration). Di default contiene `offline_access` e
`uma_authorization`, e puo' accumulare altri ruoli se qualcuno li aggiunge
alla sua lista di composites (es. via Console).

`one-piece-user-service` non usa questo meccanismo: i ruoli di un utente
invitato sono assegnati esplicitamente in `assignRealmRoles`
(`KeycloakUserDirectoryAdapter`), e `keycloak.admin.excluded-realm-roles`
gia' filtra `default-roles-onepiece`, `offline_access` e
`uma_authorization` dalla lettura dei ruoli - ma solo dalla visualizzazione,
non dall'assegnazione reale, che restava comunque attiva lato Keycloak.

## Decisione

`default-roles-onepiece` e' dichiarato esplicitamente in
`realm-onepiece.json` con `composites: {}` (nessun ruolo realm o client
incluso). Come ogni altro campo del realm, viene riconciliato ad ogni sync
da `keycloak-config-cli` (ADR-0011), quindi corregge anche eventuali
composites aggiunti a mano via Console, senza bisogno di un hook dedicato.

Nessun nuovo utente riceve piu' automaticamente `offline_access` o
`uma_authorization`: nessuno dei due e' usato da questa applicazione
(niente refresh token offline, niente policy UMA).

## Alternative considerate

- **Rimuovere il ruolo via Admin API dopo la creazione, per singolo
  utente** (in `createUnactivatedUser`): scartata - aggira il meccanismo
  invece di correggerne la causa, aggiunge una chiamata Admin API per ogni
  creazione, e non copre gli utenti creati fuori da questo flusso (es. da
  Admin Console).
- **Lasciare invariato e ampliare solo `excludedRealmRoles`**: scartata -
  risolve solo il sintomo (i ruoli non voluti restano visibili in nessuna
  lista dell'app) ma non la causa: i ruoli sarebbero comunque assegnati
  davvero in Keycloak.

## Conseguenze

- Se in futuro un client avra' bisogno di `offline_access` (refresh token
  offline) o di policy UMA, quel ruolo va riassegnato esplicitamente li' -
  non piu' implicito per ogni utente del realm.
- Un nuovo utente Keycloak, appena creato e prima di qualunque assegnazione
  esplicita, non ha alcun ruolo realm - coerente con l'assegnazione sempre
  esplicita gia' in uso in `KeycloakUserDirectoryAdapter`.
