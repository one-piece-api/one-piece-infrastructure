terraform {
  required_version = ">= 1.15"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.27"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
