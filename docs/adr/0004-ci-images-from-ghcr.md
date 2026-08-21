# ADR-0004: Immagini da GHCR nella CI di questo repo

## Contesto

Il workflow `.github/workflows/test-infrastructure.yml` esegue
`./scripts/setup.sh` (cluster kind + `helmfile sync` + smoke test) per
verificare che le istruzioni committate in questo repo mettano davvero in
piedi lo stack. Da quando `user-service`/`user-frontend` sono release reali
(ADR-0003), quel job non completa mai il giro: i chart puntano a
`one-piece-user-service:local`/`one-piece-user-frontend:local` con
`imagePullPolicy: IfNotPresent`, immagini che in locale vengono costruite a
mano e caricate con `kind load docker-image` — passaggio che il workflow CI
non esegue mai. I Pod restano quindi in `ErrImageNeverPull` finché
`helmfile sync` non va in timeout.

Nel frattempo `one-piece-user-service` e `one-piece-user-frontend` (repo
applicativi) pubblicano immagini reali su GHCR
(`ghcr.io/one-piece-api/user-service`, `.../user-frontend`) ad ogni push su
`main`, tag = versione applicativa + `latest`.

## Decisione

### Due ambienti Helmfile: "default" e "ci"

`helmfile.yaml` guadagna un blocco `environments:` (feature nativa di
Helmfile, non uno script custom) — cosa che richiede rinominare il file in
`helmfile.yaml.gotmpl`, perché in Helmfile v1 solo quell'estensione abilita
il templating Go usato per leggere `.Values.*` nei `values:` delle release;
`helmfile sync`/`build` continuano a scoprirlo automaticamente, nessun `-f`
esplicito necessario. L'ambiente `default` (invariato,
`helmfile sync` senza flag) mantiene il comportamento locale esistente —
immagini `:local`, nessun pull secret. L'ambiente `ci`
(`helmfile --environment ci sync`, invocato da `scripts/setup.sh` tramite
la variabile `HELMFILE_ENVIRONMENT`, impostata a `ci` nel workflow) fa
puntare `user-service`/`user-frontend` a `ghcr.io/one-piece-api/...:latest`
con `imagePullPolicy: Always` (obbligatorio con un tag mutabile).

Risultato: la CI verifica lo stack con le stesse immagini che finirebbero
in un deploy reale, non un placeholder — un check infrastrutturale end-to-
end genuino, non solo la sintassi dei manifest.

### Package GHCR privati + imagePullSecrets

I package pubblicati con `GITHUB_TOKEN` sono privati di default. Invece di
renderli pubblici (alternativa più semplice ma meno rappresentativa di un
ambiente enterprise reale), i Pod nell'ambiente `ci` referenziano un
`imagePullSecrets` (campo aggiunto ai chart `user-service`/`user-frontend`,
lista vuota di default — zero diff per l'ambiente locale). Il Secret
(`ghcr-pull-secret`, namespace `app`) è creato da un hook presync
(`scripts/create-ghcr-pull-secret.sh`, stesso idioma già in uso per il
realm Keycloak e il secret di oauth2-proxy) a partire da un Personal
Access Token dedicato (`GHCR_PULL_TOKEN`, scope `read:packages` soltanto —
principio del privilegio minimo, separato dal `GHCR_CLEANUP_TOKEN` usato
nei repo applicativi per la cancellazione delle versioni untagged) salvato
come secret dell'organizzazione. In locale `GHCR_PULL_TOKEN` non è
impostata: lo script lo rileva e non fa nulla.

## Alternative considerate

- **Package GHCR pubblici**: elimina interamente la necessità di
  `imagePullSecrets`/PAT dedicato. Scartata a favore di un setup più
  vicino a un ambiente enterprise reale (registry privato), per valore
  educativo — vedi sezione "Educational Workflow" delle linee guida.
- **Build delle immagini direttamente nella CI di questo repo** (checkout
  dei repo applicativi, build Docker, `kind load docker-image`): duplica
  la pipeline di build già esistente nei repo applicativi e accoppia
  questo repo al codice sorgente di componenti che, per scelta di
  progetto, vivono altrove (multi-repo, non monorepo). Scartata.

## Conseguenze

- Il grafo di dipendenze di Helmfile non cambia; cambiano solo i `values`
  effettivi delle release `user-service`/`user-frontend` a seconda
  dell'ambiente.
- Servono due secret a livello di organizzazione GitHub:
  `GHCR_PULL_USERNAME` e `GHCR_PULL_TOKEN` (scope `read:packages`),
  usati dal workflow di questo repo.
- La CI di questo repo verifica ora anche implicitamente che le immagini
  pubblicate dai repo applicativi siano effettivamente deployabili
  (readiness/liveness probe inclusi), non solo che esistano su GHCR.
