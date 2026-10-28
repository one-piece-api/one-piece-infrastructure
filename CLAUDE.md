# onepiece-infrastructure

kind cluster (local), single-node k3s on an Always Free Oracle Cloud VM (remote, ADR-0027), Helmfile orchestration, Keycloak realm, Terraform (OCI + Cloudflare). Setup, access and remote overview: `README.md`. Decisions: `docs/adr/` (0001–0027).

## Commands

```bash
./scripts/setup.sh                       # local cluster from zero + smoke test
./scripts/teardown.sh                    # deletes the kind cluster (asks)
helmfile sync -l name=<release>          # one release and its hooks
HELMFILE_ENVIRONMENT=ci ./scripts/setup.sh   # CI-like: GHCR images, Mailpit, 60 s invitations
```

Environments: `default` (local, `:local` images built from sibling repos), `ci`, `remote`.

## Map

| Path | Holds |
|---|---|
| `helmfile.yaml.gotmpl` | Releases, `needs:` order, per-environment values |
| `helm/charts/` | Local micro-charts; `credentials` is the single secret registry (ADR-0025) |
| `keycloak/` | Helm values and the declarative realm, synced by keycloak-config-cli (ADR-0011) |
| `scripts/` | Setup steps, hooks, realm configuration, QA seed users, vault seeding |
| `terraform/` | OCI (VM, cloud-init, network, Vault, backup bucket) and Cloudflare, applied by hand (`terraform/README.md`) |
| `kubernetes/ci-deployer.yaml` | CI identity on the remote, applied once by hand (not a helmfile release) |

## Rules

- **Pushing `main` deploys to the remote** (`deploy-remote.yml`, over WireGuard) when the repo variable `REMOTE_DEPLOY_ENABLED` is `true`: ask before pushing, as everywhere.
- **Always Free only.** Verify every OCI resource against current Oracle docs: A1 within 2 OCPU / 12 GB, boot + block volumes within 200 GB at 10 VPU, at most 5 volume backups, one reserved IP, Vault `DEFAULT` with `SOFTWARE` keys, Object Storage within 20 GB. No OKE (tenancy limit 0) and no load balancer. Anything paid is flagged to the owner, never chosen silently.
- **Secrets:** placeholders in the `credentials` chart locally/CI, `ExternalSecret` from OCI Vault on remote. Never print secret values.
- **Registry images always fully qualified** (`docker.io/library/postgres:18.6`): the registry is explicit and does not depend on runtime defaults (k3s and kind would accept short names). Only the local `:local` images loaded into kind are short.
- **Remote checks are read-only** unless the owner asks. Access only through the WireGuard tunnel (README, "Accesso del proprietario"). Admin operations go through `kcadm` inside the pod (README).
- **Pods never reach the cloud metadata address** (NetworkPolicy in chart `namespace`): a pod that needs the instance principal gets the label `onepiece-api/oci-metadata: allowed`, nothing else.
- **Manual syncs to the remote need `HELMFILE_ENVIRONMENT=remote`**: otherwise the realm import brings back the dev test users.
- The remote is being turned into production (`../docs/implementation-plan-production-remote.md`): real secrets from the Vault, no test users, data that matters. Any wipe needs the owner's explicit confirmation.

## Remote at a glance

`app.` and `auth.onepieceapi.dev`: owner only (Cloudflare rule on the owner's IPv4 and IPv6). `api.`: public. Origin (the VM, k3s ServiceLB) accepts HTTPS only from Cloudflare. Daily `pg_dump` to bucket `onepiece-backups` (14 days); restore procedure in README. Owner IP change = update tfvars + `terraform apply`. E-mail from `no-reply@mail.onepieceapi.dev` (Resend): never invite `@onepiece.local` addresses outside CI.
