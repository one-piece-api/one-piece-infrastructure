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
  description = "Indice (0-based) del fault domain da usare per il node pool ARM, tra quelli disponibili nell'AD. Utile per aggirare 'Out of host capacity' specifico di un FD: ciclare tra 0/1/2 con -var. -1 = non specificare il fault domain (auto-assegnato da Oracle)."
}

variable "allowed_client_cidr" {
  type        = string
  description = "CIDR del proprietario, es. \"203.0.113.4/32\": unico autorizzato a raggiungere il back-office (app./auth.) tramite la regola custom Cloudflare (ADR-0020) - console admin e utenti seed hanno password note (ambiente dev). Va aggiornata a mano se l'IP cambia."
}

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Token API Cloudflare \"Terraform\" (ADR-0020): Zone Read, DNS Edit, Zone Settings Edit, Zone WAF Edit, Email Routing Rules Edit sulla zona del dominio; Email Routing Addresses Edit sull'account. Solo in terraform.tfvars (escluso da git)."
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
