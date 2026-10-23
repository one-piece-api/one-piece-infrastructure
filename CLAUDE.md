# onepiece-infrastructure

kind cluster (local), OKE on Oracle Cloud (remote), Helmfile orchestration, Keycloak realm, Terraform (OCI + Cloudflare). Setup, access and remote overview: `README.md`. Decisions: `docs/adr/` (0001–0026).

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
| `terraform/` | OCI and Cloudflare, applied by hand (`terraform/README.md`) |

## Rules

- **Pushing `main` deploys to the remote** (`deploy-remote.yml`): ask before pushing, as everywhere.
- **Always Free only.** Verify every OCI resource against current Oracle docs: OKE `BASIC_CLUSTER`, Vault `DEFAULT` with `SOFTWARE` keys, the one free flexible LB at 10 Mbps. Anything paid is flagged to the owner, never chosen silently.
- **Secrets:** placeholders in the `credentials` chart locally/CI, `ExternalSecret` from OCI Vault on remote. Never print secret values.
- **Remote images must be fully qualified** (`docker.io/curlimages/curl:latest`): OKE's CRI-O rejects short names; kind accepts them, so it only fails on the remote.
- **Remote checks are read-only** unless the owner asks. Admin operations go through `kcadm` inside the pod (README).
- **Manual syncs to the remote need `HELMFILE_ENVIRONMENT=remote`**: otherwise the realm import brings back the dev test users.
- The remote is being turned into production (`../docs/implementation-plan-production-remote.md`): real secrets from the Vault, no test users, data that matters. Any wipe needs the owner's explicit confirmation.

## Remote at a glance

`app.` and `auth.onepieceapi.dev`: owner only (Cloudflare rule on the owner's IPv4 and IPv6). `api.`: public. Origin accepts HTTPS only from Cloudflare. Owner IP change = update tfvars + `terraform apply`. E-mail from `no-reply@mail.onepieceapi.dev` (Resend): never invite `@onepiece.local` addresses outside CI.
