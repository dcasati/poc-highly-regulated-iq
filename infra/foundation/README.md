# Private AI foundation

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

- Foundation uses account/project API `2025-06-01` with creation-time agent network
  injection, explicit nonshared AAD project connections and a native Agents
  capability host at `2025-04-01-preview`. Preview acceptance is synthetic-only.
- Terraform owns the three project connections and single capability host in this
  flow. Native Foundry owns the generated Blob containers and Cosmos database.
  Do not duplicate connections/hosts or create/import the service-generated data.
- Scenario owns application containers, app identity/RBAC, Premium ACR, registry PE,
  runtime, analyzer/index/indexers/knowledge and its operator project connection.
- Build root owns only the optional ACR agent pool. Foundation reserves its subnet
  and registry DNS zone, not a registry, pool or build.
- Existing router/NAT/VM/backend and tailnet/OS DNS settings remain unchanged.

The optional, separately planned `provision_platform_egress` stage adds its own
outbound-only Standard NAT/public IP for build/runtime, never the agent subnet.
Existing NAT ownership is untouched. NSGs retain deny-other-egress and permit
only documented MCR/first-party CDN and platform service tags/ports. Build
Storage dependencies use the documented Storage service tag; runtime Storage is
region-scoped. Customer service endpoints remain private. No arbitrary NuGet
CDN or Internet/AzureCloud wildcard is allowed: use a reviewed offline package
source for the locked ACR build. NAT/public IP and pool allocation incur costs.
These controls are not per-FQDN filtering or FIPS/readiness evidence; stricter
organizational policies require a separately reviewed firewall.

The Data Zone model SKU permits inference within its selected data zone, not only
the resource's region. Use a region and SKU permitted by this root's validation
rules. Verify model availability/capacity and both Content Understanding
processing boundaries separately. Serverless is supported by the documented
standard setup; confirm native provisioning accepts its required throughput
capacity rather than setting a provisioned RU/s budget.

The documented Terraform capability-host sample references three keyless stores,
not a Key Vault. Generic standard-setup guidance still lists Key Vault. No unused vault,
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

The foundation owns the always-blocking `chat-prompt-shields` RAI policy and
its association with the chat deployment only. It retains default harm and
protected-material protections and enables the native user-prompt and indirect
attack detectors. Embedding configuration, IAM and private networking are
unchanged. Review this policy/model update in a full saved foundation plan.
Azure can append service-owned Defender/tool-stage filters on readback.
AzAPI manages the declared filters by their `(name, source)` identity and
preserves undeclared entries; it does not ignore changes to our blocking
flags, thresholds or policy mode. Do not ignore the entire filter list or
copy service-generated defaults into the template.

The managed prompt agent owns its task boundary. Use
[`review-agent.instructions.txt`](review-agent.instructions.txt) when creating
or reviewing a new version of the existing agent, preserving its model,
metadata and tools. Attach the verified policy's full ARM ID through
`definition.rai_config.rai_policy_name`, and verify the created version actually
retains it. Confirm the policy exists before assigning it: a missing policy
reference can fail open. Never replace/delete prior versions as a rollout step.
The web app does not classify intent, run safety judges or implement a
parallel prompt-injection policy.

Prompt Shields does not classify every benign off-topic request as a jailbreak;
the managed agent's whole-request scope refusal also matters. Test the exact
mixed review/Python request, paraphrases, forged history, and document/field
instructions through the native service, as well as valid reviewed-case
questions. Policy association or a successful response alone is not proof of
protection. The classic document-delineation contract documents Chat Completions;
do not assume equivalent Responses document coverage without runtime evidence.
Task Adherence is not enabled here: its processing-residency suitability has not
been reviewed for the selected boundary, and alignment with user intent alone
does not enforce an application domain boundary. These controls reduce risk;
they do not guarantee prevention of every injection.

1. **Dependencies/account/models:** leave all stage flags false. Account creation
   includes private networking but no `capabilitySettings`. Existing scoped caller
   Blob/Cosmos grants are retained for operator access, not mistaken for the
   project's provisioning identity. Search operator and Content Understanding roles
   are scoped to new services.
   The requested Search-to-application-Blob link is not automatically approved.
2. **Private verification:** inspect ordinary PE states and returned IPs; separately
   approve exact normal service hostnames and private-link CNAME split DNS. Verify
   normal OS DNS, private TLS and keyless access from the approved host. Wait for
   caller-role propagation. Private IPs or a successful apply alone are insufficient.
3. **Project:** set `private_connectivity_verified` and `provision_project` only
   after those checks, then review a new saved plan. This creates the project and
   caller project-scoped **Foundry User** role (formerly Azure AI User), not
   connections, a capability host or runtime permissions. Match the management
   response's exact project ARM ID and system identity; its `name` can be the
   hierarchical `account/project` rather than the bare child name.
   Do not create an agent before its BYO store configuration is complete.
4. **Provisioning identity/connections:** discover the actual project system
   identity and record its association in `agent_provisioning`. Set
   `configure_agent_provisioning` in a separate plan. Its identity precondition
   rejects a different principal. Three nonshared AAD connections reference the
   actual agent Blob, Cosmos and Search IDs; no credentials are included. Grant
   project Storage Blob Data Contributor on agent Storage, Cosmos DB Operator on
   agent Cosmos, and both Search contributor roles on the selected Search service.
   These are project provisioning grants, not caller grants.
5. **Capability host:** verify the successful live grants, actual principal/scopes, connection targets
   and private connectivity; update the evidence reference and set
   `capability_provisioning_verified`. Enable `provision_agent_capability` in a
   separate saved plan. The native host references connection **names**, not
   `capabilitySettings` ARM IDs, and must finish its bounded 30-minute creation.
   The connection CRUD API has no standalone project-identity access test.
   Management-plane role visibility or a fixed sleep does not prove service-side
   authorization propagation. The host create performs the next native provisioning
   check; preserve state and surface authorization failures rather than broadening
   access.
   Do not claim a successful plan/host proves a working managed agent.
6. **Runtime bindings:** discover the actual project's system/user-assigned runtime
   principal IDs, service-created file/intermediate containers and Cosmos database.
   A returned project `internalId` can be a compact 32-character UUID; normalize
   its UUID representation when checking the observed container association.
   Do not construct container names from it: discover the actual names, including
   service-generated suffixes, and verify their documented runtime roles.
   Verify their association with this project, record a nonsensitive evidence
   reference, and fill `agent_runtime`. Enable `configure_agent_runtime` in a
   separately reviewed plan. ARM data reads verify stores exist under the selected
   agent accounts; identity association is an operator verification, not inferred
   from a GUID. The actual project system identity must be included. Roles target
   those containers/database, never application or Terraform state containers.
   This plan deliberately removes the temporary project account-wide Blob Data
   Contributor grant while adding the discovered container roles; explicitly review
   that access revocation. The project Cosmos operator and Search grants remain,
   without duplicate role assignments; separately verified extra runtime identities
   receive their own scoped grants. Storage Account Contributor is scoped only to
   the agent account. A non-Succeeded capability host blocks runtime configuration.
7. **Private data-plane bootstrap:** use ephemeral Entra authentication to configure
   Content Understanding defaults with the returned `chat`/`embedding` deployment
   names. Before configuration, a defaults GET can return HTTP 400 with inner
   error `DefaultsNotSet`; this is not proof of a private-network failure or of
   configured models. Verify DNS/TLS/authentication separately, then configure
   and read back the supported defaults under the bootstrap approval.
   Check analyzer supported models and the selected processing boundary. Bootstrap a
   prompt agent without unrestricted retrieval tools and verify a synthetic request.
   Content Understanding defaults and prompt-agent inference are independent
   readiness checks; a working agent does not establish extraction readiness.
   These actions are not run by Terraform provisioners or this root.

   Use the [documented model/defaults contract](https://learn.microsoft.com/azure/ai-services/content-understanding/concepts/models-deployments):
   `PATCH /contentunderstanding/defaults?api-version=2025-11-01` with a
   `modelDeployments` map, then GET and compare the returned mappings. Keys are
   supported model names or prebuilt aliases; values are actual deployment names,
   not model versions. Check the live analyzer's `supportedModels` before choosing
   them. Configure the selected completion/embedding model names and the
   `prebuilt-analyzer-completion`, `prebuilt-analyzer-completion-mini` and
   `prebuilt-analyzer-embedding` aliases needed by native processing. An alias
   does not require a new deployment when an existing compatible model is
   supported. Preserve unrelated defaults and stop on conflicting mappings.
   Successful readback establishes configuration, not successful extraction.

### Prompt-agent bootstrap and private smoke test

The [Exempt Agent baseline definition](../../agents/exempt-agent/definition.json)
uses the foundation's `chat` deployment and no tools. For a reviewed rollout,
replace its baseline instructions with the current
[`review-agent.instructions.txt`](review-agent.instructions.txt) and attach the
verified full native RAI policy ID as described above; the baseline's diagnostic
marker exception is not the current restricted-scope policy. Preserve the
existing agent's metadata/description and prior versions. Read back
`model_deployments.chat` and verify that deployment before using the definition;
if another foundation supplies a different name, substitute its actual output.
Use the selected project's normal private endpoint with trusted TLS and an
ephemeral `https://ai.azure.com/` audience token. Never save or print the token.

For the New Agent Service `2025-11-15-preview` contract, inspect
`GET <project-endpoint>/agents?api-version=2025-11-15-preview` first. Preserve an
existing agent; review its versions/definition rather than silently replacing it.
Create a missing agent with `POST` to the same path, using
`{"name":"exempt-agent","definition":<reviewed definition>}`; for an existing agent,
create a separately reviewed new version only when its definition needs updating.
Read back the version from
`/agents/exempt-agent/versions?api-version=2025-11-15-preview` and confirm the
model, current scope instructions, full native RAI policy association and empty
tool list. This is a separate approved data-plane
action, not part of a Terraform apply.

Invoke `POST <project-endpoint>/openai/v1/responses` with the verified name/version
in `agent_reference`, `tool_choice = "none"`, `store = false` and a synthetic
input asking an in-scope question about supplied synthetic reviewed-case evidence.
Do not ask the scope-restricted agent for an unrelated connectivity marker or supply
a shared conversation. Verify HTTP success **and** status `completed`, an
evidence-supported answer and absence of tool activity. Also verify a mixed or
unrelated request receives the whole-request refusal. The response can omit the `store` echo
field; preserve evidence that the request disabled storage without treating an
omitted echo as failure or claiming independently verified service retention.

A generic downstream-dependency error does not identify a failed Key Vault.
Verify actual native store associations and scoped grants, allow bounded
authorization propagation and retest without changing keys or public networking.
A successful host or agent-list request alone is not inference readiness.
Use the actual verified agent name in the scenario handoff. This smoke test
does not establish retrieval quality, Content Understanding, application access
or cryptographic compliance.

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

The DNS rule targets only Azure's fixed platform address `168.63.129.16/32` on
port 53. Do not use `AzurePlatformDNS` in an Allow rule: Azure rejects that
combination. Platform DNS normally bypasses NSGs unless explicitly denied with
that special tag, so the catch-all egress denial is not a DNS filtering control.
See [Azure platform IP behavior](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16).

The account/project/connection APIs and capability-host preview follow the
[official BYO-VNet Terraform sample](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-terraform/15b-private-network-standard-agent-setup-byovnet).
Unlike that sample's defaults, this root disables local authentication, uses Deny
ACLs with no bypass and preserves restrictive egress. Local AzAPI schema validation
is disabled only for the documented Foundry resources; pinned static tests do not
establish live compatibility. Do not replace the locked providers, enable keys or
trusted-service bypass, or substitute the new capability-settings preview to make
an apply succeed.

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

References: [official Terraform sample](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-terraform/15b-private-network-standard-agent-setup-byovnet),
[private networking](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks),
[standard agent setup](https://learn.microsoft.com/azure/foundry/agents/concepts/standard-agent-setup).
