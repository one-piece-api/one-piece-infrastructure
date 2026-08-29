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
  description = "CIDR autorizzato a raggiungere l'ingress HTTP/HTTPS (porte 80/443) del Load Balancer pubblico, es. \"203.0.113.4/32\" per un singolo IP. Nessun dominio/TLS ancora (ADR-0005): restringere l'accesso di rete è la mitigazione scelta finché le credenziali seed del realm Keycloak restano quelle committate in keycloak/realm-onepiece.json. Va aggiornata a mano se l'IP cambia."
}
