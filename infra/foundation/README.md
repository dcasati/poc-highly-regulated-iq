# Private US foundation

This root owns new PoC Foundry, Search S1, separate application/agent Storage,
serverless Cosmos, three dedicated subnets and baseline private connectivity.
It consumes the connectivity VNet and backend-owned endpoint subnet/Blob DNS
without importing, recreating or changing their state ownership.

Use one authoritative private-network-connected checkout and the approved isolated
CLI profile in every shell. Subscription/directory/principal guards must match
that profile. Providers are pinned, never automatically registered or upgraded.
Do not use AZD, the inherited Fabric root, local foundation state or another
project's infrastructure.

## Ownership and boundaries

- Foundation creates account capability settings with creation-time agent network
  injection; API `2026-07-15-preview` requires explicit synthetic-PoC acceptance.
- Native Foundry owns generated connections, Blob containers and Cosmos databases.
  Do not create duplicate capability hosts/connections or import those data resources.
- Scenario owns application containers, app identity/RBAC, Premium ACR, registry PE,
  runtime, analyzer/index/indexers/knowledge and its operator project connection.
- Build root owns only the optional ACR agent pool. Foundation reserves its subnet
  and registry DNS zone, not a registry, pool or build.
- Existing router/NAT/VM/backend and tailnet/OS DNS settings remain unchanged.

The US Data Zone model SKU allows inference in the US, not only the resource's
region. Verify model availability/capacity and both Content Understanding
processing boundaries separately. Serverless is supported by the documented
standard setup; confirm native provisioning accepts its required throughput
capacity rather than setting a provisioned RU/s budget.

The current keyless capability-settings contract references three stores, not a
Key Vault. Generic standard-setup guidance still lists Key Vault. No unused vault,
secret connection or customer-managed key is provisioned here. If the native
flow requires one, stop for a reviewed private configuration. Register documented
prerequisite providers only with administrator approval.

## Configure and review

Prepare one ignored `terraform.tfvars` and `backend.tfbackend` from the sanitized
examples, without overwriting existing files. Keep them owner-only. Backend
credentials, tokens, state, saved plans and logs must never enter Git.

Search uses Entra-only authentication with no network bypass. With the pinned
AzureRM provider, omit `authentication_failure_mode` when
`local_authentication_enabled = false`; the two settings are incompatible.
Mocked tests do not replace the real-provider live plan that checks this contract.

Use the existing private/keyless backend and distinct `foundation/terraform.tfstate`
key. Verify it has no existing owner before initializing. A missing local file is
not permission to migrate state or create a new state store.

```sh
cd infra/foundation
# Set the previously approved ARM_SUBSCRIPTION_ID and AZURE_CONFIG_DIR in this shell.
terraform init -input=false -backend-config=backend.tfbackend
terraform validate
terraform plan -input=false -out=foundation-platform.tfplan
# Obtain explicit approval of this exact saved plan before:
terraform apply foundation-platform.tfplan
```

Review actual costs, scoped caller/service roles, preview behavior, networking and
all changes. Never use automatic approval, targeted apply, force-unlock, imports,
replacement or deletion as a recovery shortcut. `prevent_destroy` protects durable
resources, not secrets from appearing in secured provider state.

## Native stages

1. **Dependencies/account/models:** leave all stage flags false. Caller Blob Data
   Contributor on agent Storage and Cosmos DB Operator precede account creation.
   Search operator and Content Understanding roles are scoped to new services.
   The requested Search-to-application-Blob link is not automatically approved.
2. **Private verification:** inspect ordinary PE states and returned IPs; separately
   approve exact normal service hostnames and private-link CNAME split DNS. Verify
   normal OS DNS, private TLS and keyless access from the approved host. Wait for
   caller-role propagation. Private IPs or a successful apply alone are insufficient.
3. **Project:** set `private_connectivity_verified` and `provision_project` only
   after those checks, then review a new saved plan. The project inherits account
   capability settings; generated store connections are immutable. Changing stores
   requires destructive project recreation and is not automated.
4. **Runtime bindings:** discover the actual project's system/user-assigned runtime
   principal IDs, service-created file/intermediate containers and Cosmos database.
   Verify their association with this project, record a nonsensitive evidence
   reference, and fill `agent_runtime`. Enable `configure_agent_runtime` in a
   separately reviewed plan. ARM data reads verify stores exist under the selected
   agent accounts; identity association is an operator verification, not inferred
   from a GUID. The actual project system identity must be included. Roles target
   those containers/database, never application or Terraform state containers.
5. **Private data-plane bootstrap:** use ephemeral Entra authentication to configure
   Content Understanding defaults with the returned `chat`/`embedding` deployment
   names. Check analyzer supported models and US processing behavior. Bootstrap a
   prompt agent without unrestricted retrieval tools and verify a synthetic request.
   These actions are not run by Terraform provisioners or this root.

Do not reset flags after a stage has been applied; that would request protected
resource deletion. Preserve successful state/resources on partial provisioning
failure, including subnet service-association links. Do not purge or recreate an
account/VNet to recover without separate approval.

## Networking and handoff

Agent/runtime/build allocations are respectively the VNet's first, second and
fifth `/24`; the third `/24` remains backend-owned and the router keeps its `/27`.
Each new subnet has outbound defaults disabled and an NSG permitting private
endpoint HTTPS, Azure DNS and Entra HTTPS, followed by deny-other-egress.
Default platform inbound rules are retained. No general Internet/AzureCloud
allow rule, trusted-service bypass or NAT association is added.

The new preview account/project API is advertised by the registered provider.
Local AzAPI schema validation is disabled only on those two current-contract
resources; static tests do not establish service-side preview compatibility.
ARM rejects unsupported properties during a separately approved live stage.

This is a minimum dependency baseline, not proof of platform connectivity or a
complete firewall/FQDN policy. If a required dependency is blocked, stop and review
its exact exception; never silently relax outbound rules. Runtime and build
dependencies, approved package access and optional existing-NAT routing require
review **before** the scenario environment or ACR pool is provisioned.

After verified bootstrap, `scenario_existing` supplies the scenario references;
add the actual prompt-agent name and verified service/project endpoints. Inspect
`blob_shared_link_status` and obtain target-owner approval. `build_subnet` is a
reservation, not build readiness. Keep knowledge/runtime flags false initially.

No application, private build, document extraction, indexing, retrieval, immutable
retention or FIPS certification is established by this root. Runtime/image/transport
evidence, SPA/API identities, retention and synthetic acceptance remain mandatory.

## Static checks

In an isolated configuration copy, with no deployment files/state or Azure
credentials:

```sh
terraform init -backend=false -input=false
terraform fmt -check -recursive
terraform validate
terraform test
```

Tests use mocked providers and synthetic IDs. Live plans/applies are separate
approved deployment operations, not template-maintenance checks.

References: [capability settings](https://learn.microsoft.com/azure/foundry/how-to/configure-capability-settings),
[private networking](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks),
[standard agent setup](https://learn.microsoft.com/azure/foundry/agents/concepts/standard-agent-setup).
