provider "oci" {
  auth                = "APIKey"
  config_file_profile = "DEFAULT"
  region              = var.region
}

# Token "Terraform" (ADR-0020): permessi limitati alla zona del dominio
# (DNS, impostazioni, WAF, Email Routing), solo da terraform.tfvars locale.
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
