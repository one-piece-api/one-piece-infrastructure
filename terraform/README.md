# Terraform — ambiente remoto Oracle Cloud

Provisiona le risorse OCI dell'ambiente remoto always-on descritto in
`../docs/adr/0027-k3s-on-always-free-vm.md`: compartment dedicato, rete
(VCN/subnet/security list), una VM ARM Ampere A1 (2 OCPU / 12 GB, l'intero
budget Always Free) con k3s installato da cloud-init (`compute.tf`,
`cloud-init.yaml.tftpl`), un block volume dati da 50 GB, l'IP pubblico
riservato, il bucket dei backup con scadenza a 14 giorni (`backups.tf`),
l'identità della VM per ESO e backup (`iam.tf`) e un Vault OCI (chiave
software-protected) per i secret applicativi. `oke.tf` e `import.tf`
descrivono il cluster OKE dismesso e restano fino al cutover (piano
k3s-remote, K4).

Gestisce anche la zona Cloudflare del dominio `onepieceapi.dev`
(`cloudflare.tf`, `email.tf`, ADR-0020/0023): record DNS proxied verso la VM, SSL Full (strict), regola che limita `app.`/`auth.` al
proprietario, record email di Resend, DMARC ed Email Routing. Gli intervalli
IP di Cloudflare alimentano la security list: l'origin accetta HTTPS solo da
Cloudflare.

Tutte le risorse restano nell'allowance **Always Free** — vedi l'ADR per i
limiti esatti e le scelte fatte per rispettarli (forma della VM, boot volume a
10 VPU, tipo di vault, nessuna policy di backup automatica dei volumi).

## Prerequisiti

- Account OCI Always Free attivo.
- Chiave API caricata in Console OCI (My profile → API keys), con la
  coppia di chiavi generata localmente (mai la privata via Console) e
  `~/.oci/config` compilato di conseguenza. `key_file` deve puntare alla
  chiave privata locale.
- Token API Cloudflare "Terraform" (My Profile → API Tokens → Custom token),
  limitato alla zona `onepieceapi.dev`: Zone Read, DNS Edit, Zone Settings
  Edit, Zone WAF Edit, Cache Rules Edit, Email Routing Rules Edit; sull'account Email Routing
  Addresses Edit. Consigliato il filtro sull'IP del proprietario.
- `terraform.tfvars` compilato a partire da `terraform.tfvars.example`:
  `tenancy_ocid` e `region` (stessi valori di `~/.oci/config`), token e
  account ID Cloudflare, IPv4 e prefisso IPv6 del proprietario, casella a cui
  inoltrare `contatti@`, chiave SSH del proprietario e chiavi pubbliche
  WireGuard di CI e proprietario. Il file è escluso da git.

## Se cambia l'IP del proprietario

Il back-office (`app.`/`auth.`) risponde solo a `allowed_client_cidr` (IPv4)
e `allowed_client_ipv6_cidr` (prefisso /64): i browser preferiscono IPv6,
quindi servono entrambi. Da un IP non autorizzato Cloudflare mostra una
pagina di blocco (403). Per aggiornarli:

```bash
curl -4 -s https://api64.ipify.org   # IPv4 -> allowed_client_cidr = "<ip>/32"
curl -6 -s https://api64.ipify.org   # IPv6 -> allowed_client_ipv6_cidr = "<primi 4 gruppi>::/64"
terraform plan    # una sola modifica: cloudflare_ruleset.firewall_custom
terraform apply
```

## Uso

```bash
terraform init
terraform plan
terraform apply
```

cloud-init gira solo al primo boot: un cambio a `cloud-init.yaml.tftpl` o a
`k3s_version` non ricrea la VM (si applica sulla VM, o con
`terraform apply -replace=oci_core_instance.k3s` dopo un backup). La CI
valida il template con `cloud-init schema` (`tests/cloud-init/`).

Dopo il primo boot, la chiave pubblica WireGuard del server è sulla console
seriale (la privata non lascia mai la VM):

```bash
oci compute console-history capture --instance-id "$(terraform output -raw instance_id)"
oci compute console-history get-content --instance-console-history-id <id> --length 1000000   --file - | grep 'onepiece: WireGuard server public key'
```

Accesso con `kubectl` e SSH dal tunnel: `../README.md`, «Accesso del
proprietario».

## Secret applicativi: non gestiti da Terraform

I *valori* dei secret (password Keycloak/DB, client secret OAuth2, API key
Resend, ecc.) non sono risorse Terraform, per non farli transitare in
chiaro nello state file. Vanno creati manualmente nel Vault dopo l'apply,
ad es. via OCI CLI:

```bash
oci vault secret create-base64 \
  --compartment-id <compartment_id> \
  --vault-id <vault_id> \
  --key-id <vault_key_id> \
  --secret-name <nome-secret> \
  --secret-content-content "$(echo -n '<valore>' | base64)"
```

(`compartment_id`, `vault_id`, `vault_key_id` sono negli output di
`terraform apply`.) L'External Secrets Operator nel cluster (ADR-0025) li
legge da lì per nome, con l'identità della VM.

## Nota sulla topologia di rete

Subnet pubblica unica per la VM: aperte a internet solo la 443 (intervalli
Cloudflare) e UDP 51820 (WireGuard), con le stesse regole nel firewall della
VM; 22 e 6443 solo dal tunnel. Scelta adeguata a un singolo nodo senza
requisiti di alta disponibilità. Non è la topologia "hardened" a più subnet che OCI
documenta per ambienti production-grade — va rivista se questo ambiente
dovesse evolvere oltre il suo scopo attuale.

`scripts/seed-vault-secrets.sh` crea in un colpo solo i secret usati dal
chart `credentials` (ADR-0025): casuali, più GHCR e Resend da `.env.local`.
Non sovrascrive mai un secret esistente. Il token Cloudflare DNS
(`onepiece-cloudflare-dns-token`) si carica a mano con il comando sopra.
