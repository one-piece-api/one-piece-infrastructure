variable "tenancy_ocid" {
  type        = string
  description = "OCID del tenancy OCI (vedi ~/.oci/config, campo 'tenancy')."
}

variable "region" {
  type        = string
  description = "Regione OCI (vedi ~/.oci/config, campo 'region')."
}

variable "fault_domain_index" {
  type        = number
  default     = 0
  description = "Indice (0-based) del fault domain da usare per la VM A1 (e per il node pool OKE fino alla sua rimozione), tra quelli disponibili nell'AD. Utile per aggirare 'Out of host capacity' specifico di un FD: ciclare tra 0/1/2 con -var. -1 = non specificare il fault domain (auto-assegnato da Oracle)."
}

variable "allowed_client_cidr" {
  type        = string
  description = "CIDR del proprietario, es. \"203.0.113.4/32\": unico autorizzato a raggiungere il back-office (app./auth.) tramite la regola custom Cloudflare (ADR-0020) - console admin e utenti seed hanno password note (ambiente dev). Va aggiornata a mano se l'IP cambia."
}

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Token API Cloudflare \"Terraform\" (ADR-0020): Zone Read, DNS Edit, Zone Settings Edit, Zone WAF Edit, Cache Rules Edit, Email Routing Rules Edit sulla zona del dominio; Email Routing Addresses Edit sull'account. Solo in terraform.tfvars (escluso da git)."
}

variable "cloudflare_account_id" {
  type        = string
  description = "ID dell'account Cloudflare (dashboard, colonna destra della home): serve agli indirizzi di destinazione di Email Routing (ADR-0023). Non è un segreto."
}

variable "public_domain" {
  type        = string
  default     = "onepieceapi.dev"
  description = "Dominio pubblico del progetto (ADR-0020), zona su Cloudflare."
}

variable "allowed_client_ipv6_cidr" {
  type        = string
  description = "Prefisso IPv6 del proprietario, es. \"2001:db8:1:2::/64\" (il /64 della rete di casa): Cloudflare risponde anche in IPv6, e un browser dual-stack lo preferisce. Stesso ruolo di allowed_client_cidr nella regola del back-office (ADR-0020). Va aggiornato a mano se il provider cambia prefisso."
}

variable "email_routing_destination" {
  type        = string
  description = "Casella del proprietario a cui Cloudflare Email Routing inoltra contatti@<dominio> (ADR-0023). Solo in terraform.tfvars: un indirizzo personale non va in git."
}

variable "kubernetes_version" {
  type        = string
  default     = "v1.36.4"
  description = "Versione Kubernetes di cluster e node pool OKE. Fissata di proposito: un upgrade del control plane è una scelta esplicita, non un effetto di terraform apply. Elenco delle versioni offerte: oci ce cluster-options get --cluster-option-id all."
}

variable "k3s_version" {
  type        = string
  default     = "v1.36.5+k3s1"
  description = "Versione k3s installata da cloud-init (ADR-0027). Fissata di proposito; aggiornarla insieme all'upgrade fatto sulla VM, così una VM ricreata parte alla stessa versione (README.md, \"Aggiornare k3s\"). Elenco: https://github.com/k3s-io/k3s/releases."
  validation {
    condition     = can(regex("^v1\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "Formato atteso: v1.36.5+k3s1."
  }
}

variable "owner_ssh_public_key" {
  type        = string
  description = "Chiave SSH pubblica del proprietario (riga di ~/.ssh/id_ed25519.pub), installata alla creazione della VM. SSH è raggiungibile solo dal tunnel WireGuard."
}

variable "wireguard_ci_public_key" {
  type        = string
  description = "Chiave pubblica WireGuard del peer della CI (deploy-remote.yml); la privata sta solo nei secret di GitHub. Letta solo alla creazione della VM: dopo, i peer si cambiano sulla VM."
  validation {
    condition     = can(regex("^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw480]=$", var.wireguard_ci_public_key))
    error_message = "Chiave WireGuard attesa: 44 caratteri base64 (output di wg pubkey)."
  }
}

variable "wireguard_owner_public_key" {
  type        = string
  description = "Chiave pubblica WireGuard del proprietario; la privata resta sul suo PC. Letta solo alla creazione della VM: dopo, i peer si cambiano sulla VM."
  validation {
    condition     = can(regex("^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw480]=$", var.wireguard_owner_public_key))
    error_message = "Chiave WireGuard attesa: 44 caratteri base64 (output di wg pubkey)."
  }
}
