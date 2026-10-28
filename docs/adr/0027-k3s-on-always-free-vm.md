# ADR-0027: Ambiente remoto su k3s in una VM Always Free al posto di OKE

## Contesto

Il Free Trial di Oracle è scaduto il 2026-10-22: l'account resta sui soli servizi
Always Free, e il proprietario esclude il passaggio a Pay As You Go. Il tenancy ha ora
`container-engine cluster-count = 0`: OKE non è consentito. Dal 2026-10-27 l'API del
cluster (6443) non risponde, il deploy fallisce ("cluster unreachable") e Oracle può
rimuovere cluster e node pool, nodi compresi, entro la fine del periodo di grazia
(30 giorni). I dati sono stati salvati il 2026-10-28 (backup del volume e `pg_dump`,
ripristino provato in locale senza errori).

Limiti Always Free letti sull'account e sulla documentazione Oracle (2026-10-28): A1
2 OCPU / 12 GB in tutto; 200 GB tra boot e block volume, 5 backup; un Flexible Load
Balancer da 10 Mbps; un IP pubblico riservato; Object Storage 20 GB; Vault con chiavi
software e 150 segreti; 10 TB al mese in uscita.

L'alternativa "VM singola + k3s auto-gestito" era stata scartata in ADR-0005 perché
lasciava allo sviluppatore il control plane. Ora un control plane gestito gratuito non
esiste più.

## Decisione

- **Runtime**: una VM `VM.Standard.A1.Flex` da 2 OCPU / 12 GB, Ubuntu 24.04 LTS ARM,
  boot volume da 50 GB (10 VPU, non oltre: le prestazioni maggiori sono a pagamento).
  k3s a nodo singolo (server che esegue anche i pod), installato da cloud-init, con
  `--disable=traefik` e `--secrets-encryption`. Chiave SSH del proprietario alla
  creazione.
- **Accesso di CI e proprietario**: WireGuard gestito da noi, solo UDP 51820 aperta a
  internet. 6443 e 22 chiuse a internet; il firewall della VM limita il peer della CI
  alla 6443. Chiave della CI nei secret di GitHub.
- **Ingresso**: ServiceLB di k3s (porta del Service `LoadBalancer` aperta sulla VM).
  L'IP riservato 84.8.249.65 passa dal Load Balancer alla VM; il DNS Cloudflare non
  cambia. La 443 resta aperta solo agli intervalli Cloudflare (ADR-0020); Envoy
  Gateway, cert-manager DNS-01 e `CF-Connecting-IP` restano invariati, senza le
  annotazioni OCI. Firewall anche sulla VM.
- **Storage**: `local-path` di k3s su un block volume dedicato da 50 GB
  (`--default-local-storage-path`), separato dal sistema operativo. Backup: CronJob
  `pg_dump` giornaliero su Object Storage, 14 giorni (D5 del piano production-remote);
  backup del volume solo a mano, prima delle operazioni rischiose.
- **Segreti**: invariati (ADR-0025): ESO con OCI Vault e instance principal. Una
  NetworkPolicy, in ogni ambiente, blocca ai pod l'indirizzo metadata
  `169.254.169.254`, tranne ESO e il CronJob dei backup. Dynamic group rinominato
  `onepiece-instances`.
- **Migrazione**: un unico passaggio con fermo: dump finale, eliminazione di OKE e del
  Load Balancer, nuova VM, `pg_restore`, `helmfile sync`. Il volume vecchio resta fino
  alla verifica. Nessun e2e sul remoto (la suite scrive dati): verifica con `curl`,
  conteggi e login del proprietario.
- **Locale e CI invariati** (kind). La CI di questo repo aggiunge controlli statici di
  `remote`: `helmfile --environment remote template`, `terraform validate`,
  `cloud-init schema`.

## Alternative considerate

- **Pay As You Go per tenere OKE**: escluso dal proprietario (costo zero obbligatorio).
- **Due VM da 1 OCPU / 6 GB (server + agent)**: nessuna alta disponibilità in più (un
  solo server), più consumo di base e manutenzione doppia.
- **Server k3s su VM AMD micro (1 GB)**: memoria sotto il minimo di k3s server.
- **Riuso dei due nodi OKE**: nessun accesso root (niente chiave SSH, Run Command senza
  `sudo`) e istanze gestite da OKE, che Oracle può rimuovere.
- **Tailscale**: il deploy ha usato ~1637 minuti in 30 giorni contro i 1000 minuti di
  nodi ephemeral del piano gratuito.
- **Runner self-hosted sulla VM**: sconsigliato da GitHub per i repository pubblici.
- **Flux/Argo (GitOps)**: non eseguono gli hook di Helmfile; controller permanente.
- **Cloudflare Tunnel / Access**: Zero Trust richiede di norma un metodo di pagamento.
- **Tunnel SSH con la 22 aperta**: servizio visibile ed esposto a tentativi continui.
- **Flexible Load Balancer OCI gestito da Terraform**: resta il tetto di 10 Mbps e una
  risorsa da allineare a mano, senza nascondere la VM (serve comunque un IP per
  WireGuard).
- **Longhorn**: nessuna replica con un solo nodo, consumo di memoria alto.
- **Sealed Secrets / SOPS, Secret creati dalla CI**: già scartati (ADR-0025, ADR-0005).
- **k3d in locale e in CI**: rompe il vincolo di locale e CI invariati.

## Conseguenze

- Upgrade di k3s e del sistema operativo a carico nostro: versione k3s fissata,
  aggiornamenti di sicurezza Ubuntu automatici.
- Un solo nodo: se la VM si ferma, si ferma tutto (come già con un control plane e un
  Postgres unici).
- Banda non più limitata a 10 Mbps dal Load Balancer.
- Chiavi WireGuard da generare, ruotare e revocare a mano.
- Terraform perde `oke.tf`, `import.tf`, kubeconfig e `cluster_id`; acquista VM, volume
  dati e cloud-init. `deploy-remote.yml` perde l'OCI CLI e usa WireGuard.
- Supera di ADR-0005 le sezioni "Runtime", l'alternativa "VM singola + k3s" e il
  kubeconfig generato via OCI CLI; di ADR-0019 le annotazioni OCI del Load Balancer.
