# Private US Terraform state backend

This isolated root bootstraps a **new PoC-owned US backend** against the already verified PoC connectivity VNet. It does not adopt another project's storage, networking or state. Every plan and apply runs on the chosen authoritative checkout; the connectivity root remains its existing state owner.

## Design

| Component | Scope |
| --- | --- |
| Account | New Standard StorageV2, Hot/LRS, selected US region, Microsoft-managed encryption plus infrastructure encryption. No cross-tenant replication. |
| Authentication | Entra ID; Shared Key, local users and anonymous Blob access disabled. Minimum TLS 1.2 and HTTPS only; not a FIPS claim. |
| Networking | Public access disabled, firewall default Deny with no bypass. New Blob private endpoint in the reserved third `/24` of the PoC VNet. No VNet peering or existing-subnet modification. |
| DNS | New PoC-owned Blob private zone/link. Private DNS is a global Azure resource, not a region-pinned data store. |
| State | Private `tfstate` container; blob versioning and 30-day blob/container soft delete. No automatic version expiration or WORM policy that would prevent Terraform locking/writes. |
| Access grant | Storage Blob Data Contributor to the current verified deployment identity, scoped only to this new container. The VM and application receive no state access. No new identity, tenant permission or subscription-wide grant. |
| Protection | `prevent_destroy` on the resource group, account, container, endpoint subnet and DNS zone. These shared PoC resources must retain their state owner. |
| Cost | Storage/versions/transactions and private endpoint processing/allocation are billable; this root creates no VM, NAT gateway, AI service or registry. |

The pinned AzureRM 5.8 resources use ARM management APIs for account/blob-service/container provisioning. This avoids needing a temporary public-access exception or preexisting Blob DNS/RBAC during bootstrap. Providers do not automatically register namespaces. The caller needs the selected subscription's ARM creation and scoped role-assignment rights; future Blob access still requires working private DNS, routing and RBAC propagation.

Follow [developer authentication guidance](../../docs/development.md#authenticate-separately) when multiple CLI identities are cached. Subscription-scoped CLI access alone does not prove the native backend selects the same principal. Reuse the approved isolated CLI profile in each shell; do not broaden state permissions.

## Bootstrap, review and apply

The explicitly approved exception permits **this root only**, in addition to the existing connectivity bootstrap, to use owner-only local state temporarily on the encrypted authoritative Mac. It does not authorize local state for the AI foundation/scenario/build roots or automatically authorize migration.

The bootstrap steps below apply before backend activation. Once `backend.azurerm.tf` is active, initialize only the confirmed existing remote account/container/key through the ignored backend configuration; do not repeat a fresh local bootstrap or create another state owner.

Create one ignored owner-only `terraform.tfvars` from the sanitized example. Verify network names against the actual PoC outputs, region/tags and the current deployment identity type. Keep subscription selection in standard `ARM_SUBSCRIPTION_ID`/CLI conventions. Do not print state, tokens, returned keys, real tfvars or plan JSON; provider-returned secrets can exist in state even when Shared Key use is disabled.

```sh
cd infra/state-backend
umask 077
terraform init -input=false
terraform fmt -check
terraform validate
terraform test
terraform plan -input=false -out=state-backend.tfplan
# Review costs, this container-scoped identity grant, private networking and all changes.
# Only after approval of this exact saved plan:
terraform apply state-backend.tfplan
```

Tests mock Azure; they do not grant permissions, create resources or prove live connectivity. Do not apply an unpublished/unreviewed source change, use AZD, targeted applies or automatic approval. Preserve partial state on failures; do not delete successful assets or enable public access to recover.

## Private access before migration

Verify the endpoint connection is Approved, the new account remains private/keyless, versions/retention are set, and the expected identity grant exists. Use the actual `blob_hostname` output to configure **that exact hostname and its exact private-link CNAME** as restricted split-DNS domains through the US router's Tailscale address. For a verified account named `<account>`, these are `<account>.blob.core.windows.net` and `<account>.privatelink.blob.core.windows.net`. A client can resolve the CNAME separately, so routing only the original hostname can still produce a public answer. In a shared tailnet, do not replace global Azure service-suffix DNS and affect unrelated projects. Tailnet DNS/ACL changes need separate administrator approval.

On macOS, verify both names through normal OS resolution, not only Tailscale's internal resolver. If existing supplemental resolvers prevent the approved routes from reaching the OS, obtain separate approval before adding exact-hostname files under `/etc/resolver`, each pointing only to the router. Preserve existing DNS settings. Refresh stale DNS caches locally when necessary; administrator authentication remains with the operator.

From the authoritative Mac, verify normal OS DNS resolves the Blob hostname to the PoC endpoint prefix and validated HTTPS uses the private endpoint without a resolver override or certificate bypass. Direct `dig @router` alone does not verify OS/provider DNS. Then verify authorized keyless Blob access with `az storage container show --auth-mode login`; bound retries for RBAC/DNS propagation, and report failure rather than falling back to account keys.

## Separately approved migration

Obtain explicit approval for each existing local state's exact source, target account/container/key and encrypted retention. Never configure a second state owner from a fresh App worktree, use `init -reconfigure` as a substitute for migration, overwrite a target blob or delete local state/backups automatically.

Before migration, verify source lineage/serial without printing resource attributes and confirm that the intended target key does not already contain state. Activate an empty native `azurerm` backend block based on `backend.azurerm.tf.example`, and create owner-only ignored backend configuration based on `backend.tfbackend.example`. Use the `backend_config` outputs and a distinct key from `suggested_state_keys`, with explicit selected-subscription environment and Entra CLI authentication. Never include a SAS, account key or token.

Use native `terraform init -migrate-state` for the explicitly approved copy. Check the actual migration prompt/source/target instead of silently confirming or force-unlocking. Afterward verify remote lineage/serial, locking and a no-change plan before treating the remote backend as authoritative. Retain protected local bootstrap backups until the user authorizes cleanup. Migration of the backend's own state and connectivity state are separate from provisioning this backend.

The new US AI foundation is still a separate reviewed implementation. It must consume these PoC-owned network/DNS outputs without importing this root's resources. Foundation, scenario and build-pool roots must start with distinct keys in this secured remote backend.
