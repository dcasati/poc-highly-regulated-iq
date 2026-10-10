# Standalone native Bicep infrastructure

Standalone Bicep for the complete private document-review PoC. The **new-solution
path has no Terraform dependency**: start with `main.bicep`, then follow the native
ordered stages in [the standalone runbook](../../docs/bicep-deployment.md).
Today's live deployment remains separately owned.
These files do not authorize deployment, resource adoption or state migration.
Do not apply Bicep over Terraform-owned resources, even when names appear to match.
Choose exactly one owner for each boundary, with separate migration review if that
choice changes. The inherited Fabric platform is not part of this solution.
No Terraform outputs/state/configuration, state backend or precreated service is
required. Existing-resource interfaces on individual stage entries are intentional
handoffs from earlier Bicep/native stages, not an implicit Terraform prerequisite.

## Coverage and ownership

`main.bicep` and `groups.bicep` target subscription scope; other entries target a
resource group. References and
cross-RG modules stay in the selected subscription; no unrelated subscription,
tenant, network, service, peering or deployment IDs are bundled. The caller must
verify the selected subscription, directory, principal, ownership tags and region
before any separately authorized operation.

| Terraform boundary | Bicep entry point(s) | Coverage / honest parity boundary |
| --- | --- | --- |
| Entire initial new-solution foundation | `main.bicep` → `foundation/private-network.bicep`, connectivity and foundation | Owns/creates three RGs, network/NAT/VM, endpoint subnet/Blob DNS and private service/model prerequisites; no state backend. Emits complete subsequent-stage handoffs. |
| Resource groups | `groups.bicep` (subscription scope) | New connectivity/state/foundation/scenario groups only. No resources are adopted. |
| `connectivity/` | `connectivity/main.bicep` | New VNet, router subnet/NSG, egress-only NAT IP, private NIC and Trusted Launch SSH-only VM. Reuses the reviewed cloud-init source; never enrolls in a tailnet. Bicep deliberately adds deny-other-egress: exact approved bootstrap/package/tailnet destinations are required, not the Terraform router's default unrestricted outbound behavior. |
| `state-backend/` | `state-backend/main.bicep`, `grant.bicep` | New private/keyless state account, versioning/soft delete, state container, reserved endpoint subnet, Blob DNS/link and PE. A separate approved entry creates the container-scoped caller grant. Neither initializes/migrates Terraform state. |
| `foundation/` dependencies | `foundation/main.bicep` | Separate application/agent Storage, serverless Cosmos, Search S1, account/models/native blocking chat RAI, private endpoints/DNS, subnet reservations/NSGs, runtime/build controlled NAT associations and exact reviewed egress, scoped operator/service grants and Search-to-application-Blob link request. No project, host, native stores, knowledge, hosting or application. |
| `foundation/` native stages | `foundation/project.bicep`, `provisioning.bicep`, `capability.bicep`, `runtime-bindings.bicep` | Project identity; three nonshared AAD connections and provisioning grants; native Agents host; discovered container/database-scoped runtime grants. Never creates guessed service-owned containers/databases. Bootstrap-grant revocation is a separate approved deletion/readback, not incremental-template omission. |
| `highly-regulated/` platform | `scenario/platform.bicep`, `private-links.bicep` | Private Premium ACR/PE, application MI, four dedicated containers, narrow application/project/Search/container roles; only missing processing/billing link requests. Existing foundation settings remain untouched. |
| Private CU/agent bootstrap | `foundation/bootstrap-payloads.bicep` + native REST | Preserved CU defaults and supported-model aliases; hardened tools-disabled agent/new version with full native RAI policy ID and preserved metadata/description. Native operator executes reviewed requests, never silently deletes earlier versions. |
| `highly-regulated/` knowledge | `knowledge/payloads.bicep` + `native/reconcile_knowledge.py` | Declarative custom-analyzer and eight Search request bodies; focused native GET/PUT drift reconciliation and bounded same-origin async polling. Ingestion/readiness and reviewed dependency-ordered deletion remain explicit operator actions, not fake ARM resources. |
| Browser identity | `identity/api-payload.bicep`, `spa-payload.bicep`, `finalize-payloads.bicep` + native Graph | Owned single-tenant API/SPA/SP creation, v2 delegated custom scope, user-only roles, explicit owner, implicit flow disabled; PKCE in unchanged app. Preauthorization/consent/user assignments require separate administrator decisions. No credentials or directory grants. |
| `highly-regulated/` hosting | `scenario/hosting.bicep` | Conditional internal Container Apps with a literal `managedEnvironments` PE and PE-backed DNS **or** private AKS with FIPS-enabled pools, Entra RBAC, UDR egress, workload federation, private pulls and internal Istio. No simultaneous runtimes or application container in this stage. |
| `highly-regulated/` runtime | `scenario/runtime.bicep`, `aks-manifests.bicep` | Container Apps ARM workload with MI pulls, digest image, shared portal configuration and continuous worker; alternatively reviewable Kubernetes/Istio manifests, not ARM-managed Kubernetes resources. Required browser identity, knowledge and image/platform/transport acceptance. |
| `acr-build/` | `acr-build/main.bicep` | Only a new VNet-connected dedicated pool under an existing private Premium registry. Never enables public access, admin credentials or trusted-service bypass; does not run a build. |
| Optional operator MCP connection | No automatic entry point | Terraform's optional `RemoteTool` connection uses a distinct `2025-10-01-preview` contract, not the native AAD connection contract. Native operator setup, permissions and private MCP retrieval require separate review. Do not attach this unfiltered tool to the portal agent or expose it to caseworkers. |
| Lifecycle / consent / retention | Administrator/operator | Bicep incremental deployments do not implement automatic destruction protection, service data-plane deletions, user-role assignments/consent, certificate provisioning or locked immutable retention. Use approved resource locks/retention and change control separately; no complete-mode deployment as a deletion shortcut. |

Names are deterministic but intentionally **not a Terraform import mapping**.
Bicep uses `uniqueString` rather than Terraform's SHA-256 suffixes. Keep branding
3-16 lowercase letters/digits/single hyphens. Every regional entry requires an
explicit approved supported Azure region permitted by the deployment's validation
rules; model version/SKU/quota are configurable, with `Standard` or
`DataZoneStandard`, never Global SKUs.
Service availability, capacity and selected processing boundaries still need verification.
The first foundation/network stage reserves a Container Apps subnet by default;
select `hosting = 'aks'` there before creating an undelegated AKS reservation.
Changing it later is a separately reviewed network/runtime migration.

## Staging

Sanitized `examples/*.example.bicepparam` are compiler fixtures, **not deployable
configuration or approval**. Their GUIDs, endpoints, digests and evidence markers
are synthetic. They must not be used on today's live assets.
Create owner-only ignored `examples/<stage>.local.bicepparam` only after a new
boundary/target is explicitly authorized; do not copy credentials/state/tfvars
from another checkout. Retain the `using` path relative to `examples/`.

| Stage | Entry point | Required operator dependency / scope |
| --- | --- | --- |
| New solution (preferred) | `main.bicep` | New Bicep-owned boundary only; approved supported region, model pins, caller, SSH public key, administration and exact dependency-egress approval. Creates all initial prerequisites; no backend/state requirement. |
| Groups | `groups.bicep` | Selected new Bicep-owned boundary, approved supported location; subscription scope. |
| Connectivity | `connectivity/main.bicep` | `rg-<project>-connectivity`; separately approved synthetic-only VM and exact destination egress. NAT IP is not VM public ingress. Cloud-init package installation needs approved access; an empty example egress list is intentionally not operational. VM enrollment/route/ACL/exact-hostname split DNS remain separate approvals. |
| Backend | `state-backend/main.bicep` | `rg-<project>-state`; verified connectivity VNet and separate backend approval. Endpoint subnet is created in the network RG. No role grant or state migration is implied. |
| State access | `state-backend/grant.bicep` | State RG; separate container-scoped identity grant approval after verifying the state account/container. No migration is implied. |
| Foundation dependencies (individual-stage alternative) | `foundation/main.bicep` | `rg-<project>-foundation`; verified owned VNet, endpoint subnet, Blob zone and outbound-only NAT. `main.bicep` creates all of them; individually supplied existing boundaries require intentional ownership verification. No backend requirement. Caller has scoped join/RBAC rights. New Search Blob shared link needs target-owner approval. |
| Project | `foundation/project.bicep` | Actual private DNS/CNAME/TLS/keyless store access and caller-role propagation, not only PE IPs. |
| Connections/grants | `foundation/provisioning.bicep` | Discover real project system identity and service endpoints. Grants automatically target that actual identity, not a supplied guess. Three AAD connections must target the selected agent stores/Search and remain nonshared. |
| Native host | `foundation/capability.bicep` | Separate preview acceptance and verification of successful native provisioning grants/private targets. Observe host creation for at most 30 minutes; stop and preserve assets on terminal failure or timeout, without broadening access. |
| Runtime bindings | `foundation/runtime-bindings.bicep` | Host must be Succeeded. Discover actual file/intermediate containers/database and identity associations; include actual project system identity automatically, only distinct verified extra principals. Inspect existing stores; never derive names from `internalId`. Revoke the temporary grant as described below. |
| Private bootstrap | `foundation/bootstrap-payloads.bicep` + native operator | Follow the [standalone runbook](../../docs/bicep-deployment.md#cu-defaults-and-agent) for supported CU defaults, supportedModels, hardened tools-disabled prompt-agent readback and in-scope synthetic inference. Successful host provisioning does not prove inference or extraction. |
| Scenario platform | `scenario/platform.bicep` | `rg-<project>-scenario`; verified private/keyless Storage, Foundry and Search S1+ with system identity. Creates only registry/data/identity/scoped grants. Browser identity may remain absent/null in local preparation because this template has no browser/runtime parameters. |
| Shared links / knowledge | `scenario/private-links.bicep`, `knowledge/payloads.bicep`, native reconciler | Links run in Search's RG; inspect target/group pairs first. Target owners approve Blob, `foundry_account` and `cognitiveservices_account`. Native ordered reconciliation does not establish ingestion/readiness. |
| Build pool / build | `acr-build/main.bicep`, native ACR Tasks | Pool runs in existing registry RG; verify Premium/private registry, Approved PE, same-region subnet and reviewed build dependencies. Build through `az acr build --agent-pool <approved-pool>` with exact approved base-image digest, never local Docker/public workers/AZD. |
| Hosting | `scenario/hosting.bicep` | Scenario RG; use Container Apps, with controlled NAT and separate dependency-egress approval. The inherited AKS alternative is not used for this document-review path. |
| Browser registration | `identity/*-payload*.bicep` + native Graph | Explicit selected directory/owner, created API/SPA client and object IDs, exact private HTTPS redirect, separate administrator authorization. No automatic consent or user assignments. |
| Runtime | `scenario/runtime.bicep` OR `scenario/aks-manifests.bicep` | Real same-directory SPA/API registrations, Caseworker/Reviewer roles/consent, `access_as_user`, verified tools-disabled existing agent, knowledge readiness, scenario-registry image existence and exact image/platform/transport acceptance. Do not compile placeholders and treat them as evidence. |
| Acceptance | Native operator | All canonical [synthetic acceptance checks](../../docs/highly-regulated-scenario.md#7-demonstrate-readiness-using-synthetic-documents-first). No real documents before identity/network/extraction/human-review/indexing/isolation/recovery/cryptographic checks and locked retention. |

Initial preparation stops at the platform entry points: there is **no hosting,
knowledge deployment or runtime by default**, and no phantom portal URL.
`portal_url` exists only on the Container Apps runtime entry point and reads its
actual ingress FQDN. AKS manifest preparation does not emit a deployed portal URL.
Hosting and runtime are separate entries instead of Terraform stage booleans.
The hosting network contract includes the existing approved `endpoint_subnet_id`
alongside `runtime_subnet_id` and `vnet`; the AKS choice does not create a Container
Apps PE. Container Apps creates the regional Private Link zone/link/zone group and
routes the environment-domain wildcard to its actual PE-owned NIC, not the ILB.
The NIC read is dependency-ordered after the PE module; no `customDnsConfigs`
fallback or supplied IP is used. [Private Link endpoint-hour and data-processing
charges](https://azure.microsoft.com/en-us/pricing/details/private-link/) and the
separate Container Apps **Dedicated Plan Management** private-endpoint
infrastructure charge apply, including with a Consumption workload profile
([Microsoft Learn billing guidance](https://learn.microsoft.com/en-us/azure/container-apps/private-endpoints-with-dns#billing)).
DNS/workload charges remain separate; verify current regional/agreement rates
before explicit plan/cost approval. Source publication and native plan preparation
do not authorize an apply.
The [canonical networking distinction](../../docs/highly-regulated-scenario.md#literal-container-apps-private-endpoint-ingress)
requires no public inbound app/data endpoint or `publicIPAddress` assigned to the
app or its ingress gateway. Explicitly approved controlled outbound-only NAT is
acceptable and does not expose unsolicited inbound access; it is not a
private-ingress deployment blocker. A literal zero-public-IP inventory is an
optional stricter architecture, not a hosting-migration requirement. Preserve
Private Endpoints/DNS, disabled public network access, registry admin disabled,
bypass `None` and approved egress destinations; this is not unrestricted Internet
egress or IAM/permission/public-access approval. Exact native plan approvals are
unchanged.
Keep successful resources/configuration on resume; don't reinterpret incremental
deployment's retained resources as permission to reset ownership or remove grants.

Search shared-link requests use native `@batchSize(1)` serialization to avoid
conflicting updates on the same Search service. This orders the resource loop,
not independent deployments; keep other authors off that service during the stage.

## Explicit bootstrap-role revocation

`foundation/provisioning.bicep` outputs the deterministic
`temporary_blob_grant_id` for the **project identity's** temporary account-wide
Blob Data Contributor grant. After runtime container/database grants are applied
and verified, obtain separate approval to delete **that exact role assignment**.
Use one native `az role assignment delete --ids <verified-temporary-blob-grant-id>`
operation, then read back that exact assignment to verify it is absent and
independently verify the retained container roles. Readback must distinguish the
expected not-found response from authorization/network/other failures.
Do not delete the caller's operator grant or project Cosmos/Search grants.

This instruction is not approval to execute it. No script or complete-mode
deployment performs it. Incremental Bicep does not remove assignments omitted from
a later template; do not rerun the provisioning entry after revocation, because
that would restore the bootstrap grant. Never claim revocation until readback.

## Data-plane and Kubernetes operator steps

`knowledge/payloads.bicep` produces parameterized request bodies as ARM outputs,
not ARM Search/CU resources. To materialize approved outputs later, review a
separate output-only ARM deployment (or manually prepare the same reviewed bodies).
`bicep build` alone emits expressions, **not resolved REST bodies**. Do not send
an ARM template's output expressions to a service. No token is a parameter/output;
use ephemeral Entra authentication only on the approved private operator host.

1. Inspect existing scenario-owned names before writes; preserve unrelated objects
   and native-generated assets. Compare reviewed bodies and actual definitions.
2. PUT the custom analyzer (`2025-11-01`). For an approved replacement, explicitly
   review `allowReplace=true`; don't silently replace an existing analyzer.
   Follow `Operation-Location` with trusted HTTPS/audience checks and bounded
   polling (30-minute budget); accept only `Succeeded`, fail on terminal error or
   timeout. GET/read back the schema/models/processing location. Configure CU
   defaults separately, preserving unrelated mappings.
3. PUT the Search index, two data sources, native layout skillset, PDF and JSON
   indexers, source, then base using `2026-08-01-preview`, in emitted order.
   GET/read back after each write; require both private indexers to succeed with
   zero failed items and populated evidence before recording readiness.
   The custom analyzer runs in the application, not inside the layout skill.
4. Run the canonical synthetic human-review and case/owner retrieval checks.
   `case_id` and `owner_id` are filterable, but a knowledge base/MCP endpoint is
   not an authorization boundary. The unchanged application enforces both filters
   and validated references; all agent calls disable tools and conversation reuse.
5. Use `native/reconcile_knowledge.py` for reviewed declared-property drift
   reconciliation; it defaults to read-only comparison and refuses unreviewed
   analyzer replacement. It authenticates ephemerally, refuses redirects and
   cross-origin polling, and propagates native failures. A source name/kind replacement
   requires rebuilding the dependent base in a reviewed operation. Any separately
   approved teardown deletes base before source, indexers before skillset/data
   sources/index, and does not delete native service-generated objects.

For AKS, `aks-manifests.bicep` similarly emits **reviewable manifests only**:
Namespace, ServiceAccount, hardened Deployment, ClusterIP Service, STRICT
PeerAuthentication, TLS Gateway, VirtualService and destination-restricted
NetworkPolicy. Required runtime approval is the same type as Container Apps.
Materialize/review the outputs, then use native Kubernetes tooling under separate
runtime approval with Entra authentication, never cluster-admin credentials.
Check API/CRD availability locally when possible and server-side during approved
operations. Install the administrator-owned certificate secret in the correct
ingress namespace separately; it is never emitted. Apply the output ingress
Service annotation to the verified existing internal gateway Service, not a
replacement Service. Namespace and CRDs must precede dependent objects.
Resolve approved private destination/proxy CIDRs for workload HTTPS; policies
do not allow blanket HTTPS egress. Verify DNS, Istio control-plane, Entra token
exchange, all private services and default-deny behavior before acceptance.
Manifests are not schema/runtime-validated by the Bicep compiler.

## Offline validation

Use the existing Bicep CLI; no provider registration, subscription discovery,
ARM validation/what-if, deployment test or Azure write is part of these checks.

```sh
az bicep version
mkdir -p .azure/bicep-build
az bicep build --file infra/bicep/scenario/platform.bicep \
  --outfile .azure/bicep-build/platform.json
az bicep build-params --file infra/bicep/examples/platform.example.bicepparam \
  --outfile .azure/bicep-build/platform.parameters.json
python3 -m unittest discover -s infra/bicep/tests -p 'test_*.py' -v
```

The vetted native compiler is Bicep **0.44.1**. The suite compiles **every** `.bicep` and sanitized parameter example with no
warnings, tests emitted stage conditions/resource absence, native store ownership,
typed evidence/identity gates, private/keyless contracts, scoped deterministic
RBAC, new-solution module ordering/no Terraform prerequisites, controlled NAT,
native RAI/chat/agent association, Graph identity/consent boundaries,
mocked native polling/drift/auth-origin checks, missing/existing shared-link conditions, dual-indexer evidence design,
digest/worker/mesh controls and invalid compiler parameter shapes.
Temporary outputs are deleted after the suite. `BICEP_CLI` can select an existing
local compiler; it defaults to PATH or Azure CLI's installed compiler, never an
automatic install.

For later local configuration, first compile the ignored parameter file, then
supplement ARM constraints with offline semantic checks:

```sh
python3 infra/bicep/tests/validate_parameters.py \
  .azure/bicep-build/runtime.local.parameters.json \
  --expected-tenant-id <separately-verified-directory-guid>
```

This rejects examples, broad egress, regions/SKUs outside its validation rules, invalid GUIDs,
mutable/nonhex digests and missing approval/evidence; values are not printed.
CIDRs are checked collectively per port as well as individually: splitting all
IPv4 addresses across two `/1`s or four `/2`s does not evade the no-Internet rule.
No arbitrary public-prefix threshold substitutes for exact destination review.
`--allow-examples` is **only** for static fixtures. These checks cannot discover
ownership, validate live principal/service associations, prove grant propagation,
compare the selected Azure directory, verify image existence, certify schemas
against running Kubernetes/preview services or establish service readiness.
Operators must perform the canonical private preflight and approvals separately.
Compilation is not FIPS certification. Neither a FIPS node flag, private network,
ordinary image tag, installed module version nor absence of a `fips` tag proves
acceptance or incompatibility. The hard requirement is FIPS 140-3 encryption at
rest/in transit, not independent whole-app/hash/JWT certification. The typed
runtime approval defaults in the examples to `attestation_mode: 'evidence_gated'`,
requiring `encryption_standard: 'FIPS140-3'` and accepted image TLS,
platform/service and transport encryption evidence. The explicit
`attestation_mode: 'synthetic_poc_attestation_deferred'` typed branch is only for
user-authorized synthetic PoC use: `approved: false` and all three encryption
evidence fields exactly `''` are mandatory. Knowledge approval, real identity,
immutable digest, private networking, approved processing boundaries and human-review controls remain required. Both
runtime entry points output `runtime_attestation_status` as deferred/not certified
and not production ready. See [the canonical exception](../../docs/highly-regulated-scenario.md#explicit-synthetic-poc-attestation-deferral);
separate native-plan approval remains mandatory. The compiler and offline tests
reject contradictory approval/evidence/deferral, not merely document the choice.

## ARM schema references and preview limitation

Native account/project/AAD connections use `2025-06-01`; the Agents host uses
`2025-04-01-preview`, not rejected account `capabilitySettings`.
The public project schema does not include `sku`, so Bicep does not emit the
Terraform sample's redundant project SKU.
The published host type omits `capabilityHostKind`, although Microsoft's official
BYO-VNet sample explicitly requires `capabilityHostKind = "Agents"`.
Only that exact BCP037 warning is suppressed at the property; no broad validation
disable or unknown resource type is used. Live preview compatibility still
requires separately approved verification.

- [Official BYO-VNet native host sample](https://github.com/microsoft-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-terraform/15b-private-network-standard-agent-setup-byovnet/code/main.tf)
- [Project ARM contract](https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2025-06-01/accounts/projects)
- [Capability-host preview contract](https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2025-04-01-preview/accounts/projects/capabilityhosts)
- [Container Apps environment contract](https://learn.microsoft.com/azure/templates/microsoft.app/2025-07-01/managedenvironments) (explicit public-network disable)
- [ACR agent-pool contract](https://learn.microsoft.com/azure/templates/microsoft.containerregistry/2025-03-01-preview/registries/agentpools)
