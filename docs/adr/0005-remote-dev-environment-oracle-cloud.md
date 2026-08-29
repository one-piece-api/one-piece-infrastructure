# ADR-0005: Ambiente di sviluppo remoto always-on su Oracle Cloud (OKE)

## Contesto

Ad oggi lo stack esiste solo in due forme transitorie: il cluster `kind`
locale (ADR-0001/0002) e il cluster `kind` effimero creato dalla CI di
`one-piece-e2e` per ogni run. Non esiste un ambiente raggiungibile fuori
dalla macchina dello sviluppatore. L'obiettivo è un ambiente di sviluppo
sempre online, ospitato sul piano gratuito ("Always Free") di Oracle Cloud
Infrastructure (OCI), riusando lo stack Helmfile/Helm già esistente senza
introdurre un meccanismo di deploy parallelo.

## Decisione

### Runtime: OKE (Oracle Kubernetes Engine) su node pool Ampere A1

Il control plane OKE è gratuito; il node pool gira su VM Always Free
ARM Ampere A1 (2 OCPU / 12 GB RAM totali — Oracle ha dimezzato questa
allowance nel 2026, verificato in fase di provisioning contro la
documentazione corrente). Si parte con un singolo nodo che assorbe
l'intero budget, per massimizzare le risorse schedulabili:
è un ambiente dev senza requisiti di alta disponibilità. Scelto sopra una
VM singola con k3s auto-gestito perché riusa i chart Helm/Helmfile così
come sono — nessuna riscrittura concettuale rispetto a `kind` — e lascia
il control plane (upgrade, resilienza) a carico del provider invece che
dello sviluppatore.

### Nuovo ambiente Helmfile "remote"

Terzo ambiente in `helmfile.yaml.gotmpl` accanto a `default` e `ci`
(ADR-0004): stesse immagini GHCR dell'ambiente `ci`, ma con `values`
dedicati per limits/requests più stringenti (CPU/RAM condivisa tra tutti i
componenti sul budget Always Free) e per l'integrazione con External
Secrets Operator al posto degli hook presync locali che oggi creano i
secret (realm Keycloak, oauth2-proxy).

### Esposizione: ingress-nginx dietro la Flexible Load Balancer Always Free

Un Service `LoadBalancer` soddisfatto dalla Flexible Load Balancer inclusa
nell'Always Free tier (limiti esatti da verificare in console OCI al
momento del provisioning, non assunti qui). Routing per path — non per
host, in assenza di un dominio — verso oauth2-proxy (che continua a
proteggere il frontend, invariato rispetto al flow locale) e verso l'API
backend.

### TLS/DNS: nessun dominio per ora

Accesso via IP pubblico in HTTP semplice. **Gap di sicurezza consapevole**:
i flow OAuth2/OIDC e i cookie di sessione di oauth2-proxy assumono
normalmente un contesto HTTPS (cookie `Secure`, redirect URI). Finché
manca un dominio, l'ambiente va trattato come dev interno, non condiviso
con terzi. Non appena sarà disponibile un dominio (anche gratuito, es.
`sslip.io`), va aggiunto cert-manager + Let's Encrypt e va richiuso questo
gap prima di qualunque condivisione esterna.

### Deploy: CI push-based, nessun controller GitOps

Un workflow in questo repo esegue `helmfile --environment remote sync`
autenticandosi al cluster con un kubeconfig (generato via OCI CLI, salvato
come secret CI), innescato dopo la pubblicazione delle immagini su GHCR.
Nessun controller ArgoCD/Flux nel cluster: su un budget Always Free già
stretto, il consumo permanente di CPU/RAM di un controller GitOps non è
giustificato per un singolo ambiente dev. Da rivalutare se il progetto
crescerà oltre un ambiente remoto singolo.

### Secret: External Secrets Operator, backend OCI Vault

External Secrets Operator sincronizza i Secret Kubernetes da OCI Vault,
scelto come backend perché nativo OCI — nessun Vault self-hosted da far
girare nel cluster, a differenza di HashiCorp Vault. Costi/limiti Always
Free di OCI Vault da verificare in fase di provisioning (documentazione
OCI corrente, non assunti da questa ADR).

### Infrastruttura come codice: Terraform

Le risorse OCI (VCN, subnet, security list, cluster OKE, node pool, Vault)
sono definite con il provider Terraform ufficiale per OCI, coerente con
l'approccio dichiarativo già in uso nel repo (Helmfile, realm Keycloak
dichiarativo — ADR-0001).

## Alternative considerate

- **VM singola + k3s auto-gestito**: scartata — nessun control plane
  gestito gratuito, manutenzione (upgrade, resilienza) a carico dello
  sviluppatore.
- **GitOps (ArgoCD/Flux) da subito**: scartata per ora — consumo
  permanente di risorse non giustificato su un cluster Always Free già
  stretto.
- **Secret creati manualmente via CI** (`kubectl create secret` da
  GitHub Secrets, idioma già in uso in locale): scartata a favore di
  External Secrets Operator, per maggiore tracciabilità/riproducibilità
  dei secret rispetto a un meccanismo imperativo.
- **Setup manuale via console OCI**: scartata a favore di Terraform, non
  riproducibile né versionabile.

## Conseguenze

- Nuovo blocco ambiente `remote` in `helmfile.yaml.gotmpl` e nuovi
  `values` per ingress/limits/ESO.
- Nuove risorse/credenziali da provisionare: cluster OKE, OCI Vault,
  service account OCI (per Terraform e per la CI), kubeconfig come secret
  CI.
- L'assenza di TLS/dominio è un gap consapevole da richiudere prima di
  condividere l'ambiente con terzi — non un dettaglio rimandabile a tempo
  indeterminato.
- Il dimensionamento delle risorse (**2 OCPU/12 GB totali**, non 4/24 come
  nelle stime iniziali — Oracle ha dimezzato l'allowance Always Free nel
  2026) condivisi tra Keycloak, PostgreSQL, oauth2-proxy, backend,
  frontend, ingress-nginx, External Secrets Operator è un budget stretto:
  richiederà tuning aggressivo di requests/limits, e potrebbe rendere
  necessario rimandare/escludere componenti non essenziali nell'ambiente
  remoto (es. Mailpit, già sostituito da Resend nel flow reale) per far
  coesistere il resto.
