# ADR-0015: `defaultRole` di primo livello per pinnare davvero il ruolo di default

## Contesto

ADR-0012 pinna `default-roles-onepiece` a `composites: {}` dichiarandolo
come una normale entry in `roles.realm[]`. Verificato che funziona su un
realm gia' esistente (riconciliato via `keycloak-config-cli`), ma **non**
su una creazione da zero (cluster locale ricreato, CI
`test-infrastructure`, un eventuale primo bootstrap di `remote` da zero):
Keycloak crea comunque il proprio ruolo di default interno reale (quello
davvero legato al realm, con `offline_access`/`uma_authorization` di
default mai svuotati), e la nostra entry in `roles.realm[]` con lo stesso
nome diventa un doppione scollegato - Keycloak rinomina l'uno o l'altro con
suffisso `-1` per evitare la collisione di nomi.

Causa: dichiarare `default-roles-<realm>` come una normale entry in
`roles.realm[]` non dice a Keycloak "questo E' il ruolo di default del
realm" - lo fa solo il campo `defaultRole` di primo livello della
`RealmRepresentation` (lo stesso schema usato da un vero export Keycloak),
assente dal nostro `realm-onepiece.json`. Senza quel campo, l'import crea
comunque il proprio ruolo di default interno indipendentemente da cosa
c'e' in `roles.realm[]`, e la nostra entry resta un ruolo qualunque non
collegato a nulla.

Scoperto verificando dal vivo il fix del link "Torna all'app" (ADR-0013)
con un utente usa-e-getta su un cluster locale ricreato da zero per quel
test - non dalla creazione originale di ADR-0012, ne' da smoke test o CI
esistenti (nessuno controlla il contenuto dei composite del ruolo di
default, solo che login/PKCE/`/api/me` funzionino).

## Decisione

Aggiunto un campo `defaultRole` di primo livello a `realm-onepiece.json`,
accanto agli altri campi scalari del realm, che referenzia esplicitamente
`default-roles-onepiece`:

```json
"defaultRole": {
  "name": "default-roles-onepiece",
  "composite": true,
  "clientRole": false
}
```

Verificato su un cluster locale ricreato completamente da zero: un solo
`default-roles-onepiece` (nessun `-1`), riconosciuto da Keycloak come
ruolo di default reale (icona dedicata in Admin Console, naviga alla
pagina "Realm settings > Default roles"), con **zero** composite - "No
roles in this realm" nella UI, non piu' `offline_access`/`uma_authorization`
di default.

## Alternative considerate

- **Nessuna** - una volta identificato il campo mancante, non c'era un
  meccanismo alternativo per dire a Keycloak "usa questo ruolo come
  default del realm" via `--import-realm`/`keycloak-config-cli`.

## Conseguenze

- L'ambiente `remote` non ha (finora) sofferto di questo bug perche' non
  e' mai stato ricreato da zero dopo ADR-0012 - solo riavviato, e
  `--import-realm` su un realm gia' esistente trova il nome gia' presente
  senza duplicarlo. Questo fix lo rende comunque corretto anche per una
  futura ricreazione completa (disaster recovery, nuovo cluster).
- Nessun impatto sugli utenti/ambienti gia' sincronizzati correttamente:
  il campo e' idempotente, riconciliato da `keycloak-config-cli` come
  qualunque altro campo del realm.
