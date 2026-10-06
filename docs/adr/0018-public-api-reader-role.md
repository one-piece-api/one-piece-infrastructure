# ADR-0018: Ruolo di sola lettura per l'API pubblica sul database di content-service

## Contesto

L'API pubblica (`one-piece-public-api`, `implementation-plan-public-api.md` D1–D3)
espone solo i contenuti pubblicati, sempre aggiornati. Con ADR-0016 ogni servizio si
collega solo al proprio database: la public-api non potrebbe leggere quelli di
content-service. Copiarli in un database suo richiederebbe un meccanismo di
sincronizzazione (eventi, outbox) che oggi non esiste.

## Decisione

- **Eccezione circoscritta ad ADR-0016**: un ruolo `public_api_reader` può collegarsi a
  `content_service`, senza esserne proprietario.
- **Divisione dei compiti**:
  - il Job di bootstrap crea il ruolo (login, password da Secret, `CONNECT` sul solo
    `content_service`);
  - una migrazione di content-service gli concede `USAGE` + `SELECT` sul solo schema
    `published`: viste che contengono i soli contenuti pubblicati (ADR-0003 in
    `one-piece-content-service`). Le tabelle interne gli restano invisibili.
- **Ordine**: il ruolo deve esistere prima delle migrazioni, che altrimenti falliscono sul
  `GRANT`. Il Job gira prima che la release `postgresql` risulti completata, e
  content-service la dichiara in `needs`.
- **Limiti sul ruolo**, perché è il primo esposto a traffico anonimo:
  - `CONNECTION LIMIT 10`: un picco non esaurisce le connessioni condivise con Keycloak
    e gli altri servizi;
  - `statement_timeout = 2s`: nessuna query lenta tiene occupata l'istanza;
  - `default_transaction_read_only = on`: anche un `GRANT` concesso per errore non
    permetterebbe scritture.
- **Configurazione**: nuova lista `readers` nel chart `postgresql`, accanto a `databases`.
  Stesso schema di Secret (uno per consumatore, nel suo namespace: qui
  `one-piece-public-api-db-credentials` in `app`).

## Alternative considerate

- **Database proprio della public-api, alimentato da eventi**: isolamento completo, ma
  serve un'infrastruttura di messaggi e il dato arriva in ritardo. Rimandato a quando
  servirà davvero.
- **Lettura tramite le API di content-service**: nessuna eccezione al database, ma
  ogni richiesta anonima diventa una chiamata interna autenticata, e content-service
  regge anche il carico pubblico.
- **Riuso del ruolo `content_service`**: nessun ruolo nuovo, ma la public-api potrebbe
  leggere e scrivere tutto.
- **`GRANT` concessi dal Job di bootstrap**: tutto in un posto, ma le viste nascono e
  cambiano con le migrazioni di content-service; i permessi le seguono meglio lì.

## Conseguenze

- I due servizi condividono un contratto in SQL (lo schema `published`): cambiarlo
  richiede di coordinare le due release. La public-api ne verifica la forma nei test
  usando le migrazioni pubblicate come artefatto da content-service.
- Un nuovo lettore richiede una voce in `readers` e una migrazione del servizio che
  possiede i dati.
- `REVOKE ALL ... FROM PUBLIC` resta: gli altri ruoli continuano a non vedere
  `content_service`.
