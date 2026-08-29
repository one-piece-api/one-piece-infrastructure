# Terraform — ambiente remoto Oracle Cloud

Provisiona le risorse OCI per l'ambiente di sviluppo remoto always-on
descritto in `../docs/adr/0005-remote-dev-environment-oracle-cloud.md`:
compartment dedicato, rete (VCN/subnet/security list), cluster OKE (Basic,
node pool ARM Ampere A1 sull'intero budget Always Free) e un Vault OCI
(chiave software-protected) per i secret applicativi.

Tutte le risorse restano nell'allowance **Always Free** — vedi l'ADR per i
limiti esatti e le scelte fatte per rispettarli (tipo di cluster, tipo di
vault, dimensionamento del node pool).

## Prerequisiti

- Account OCI Always Free attivo.
- Chiave API caricata in Console OCI (My profile → API keys), con la
  coppia di chiavi generata localmente (mai la privata via Console) e
  `~/.oci/config` compilato di conseguenza. `key_file` deve puntare alla
  chiave privata locale.
- `terraform.tfvars` compilato a partire da `terraform.tfvars.example` con
  `tenancy_ocid` e `region` (stessi valori di `~/.oci/config`).

## Uso

```bash
terraform init
terraform plan
terraform apply
```

Il kubeconfig del cluster viene scritto in `./kubeconfig` (già in
`.gitignore` del repo). Per usarlo:

```bash
export KUBECONFIG=./kubeconfig
kubectl get nodes
```

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
`terraform apply`.) L'External Secrets Operator nel cluster (da
configurare lato Helmfile, vedi ADR-0005) li legge da lì per nome.

## Nota sulla topologia di rete

Subnet pubblica unica per endpoint API, nodi e (in futuro) Load Balancer:
scelta adeguata a un singolo ambiente dev senza requisiti di alta
disponibilità. Non è la topologia "hardened" a più subnet che OCI
documenta per cluster production-grade — va rivista se questo ambiente
dovesse evolvere oltre il suo scopo attuale.
