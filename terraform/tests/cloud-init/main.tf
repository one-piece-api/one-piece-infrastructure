# Render di cloud-init.yaml.tftpl con valori finti, per "cloud-init schema"
# nella CI (test-infrastructure.yml, ADR-0027). Nessun provider, nessuna
# risorsa: solo un output. Le chiavi di vars.json sono le stesse passate da
# compute.tf: una variabile mancante fa fallire templatefile().
#   terraform -chdir=terraform/tests/cloud-init init
#   terraform -chdir=terraform/tests/cloud-init apply -auto-approve
#   terraform -chdir=terraform/tests/cloud-init output -raw user_data
terraform {
  required_version = ">= 1.15"
}

output "user_data" {
  value = templatefile(
    "${path.module}/../../cloud-init.yaml.tftpl",
    jsondecode(file("${path.module}/vars.json")),
  )
}
