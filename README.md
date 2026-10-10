# Highly regulated private IQ proof of concept

A private document-review application on Azure, derived from [the upstream IQ template](https://github.com/dcasati/private-iq-template).

## Target audience

This proof of concept is for teams designing human-led document review in highly regulated environments. The scenario assists reviewers of Form 3500 exemption applications using manually exported PDF packages; the extraction schema is configurable rather than a bundled Form 3500-specific model.

Caseworkers upload original PDFs through an Entra-authenticated private portal. Azure AI Content Understanding extracts structured fields, confidence and source evidence. Reviewers inspect the original, correct the extraction and explicitly confirm every field before the application publishes evidence for indexing.

Reviewers can then ask questions about their selected case. The API enforces both case and owner filters, checks retrieved references and supplies the evidence and corrected fields to an existing Foundry prompt agent with all tools disabled. Answers include source references. **Human judgment remains authoritative:** the application has no business-system connectors and never makes eligibility decisions.

## Components of this solution

![Target Azure architecture for private document review, showing human validation, private evidence indexing, case-scoped retrieval and separate build and native-agent storage boundaries.](docs/diagrams/private-document-review.svg)

[View the full-size architecture](docs/diagrams/private-document-review.svg). The [scenario tutorial](docs/highly-regulated-scenario.md#architecture-and-ownership) explains the flows and ownership boundaries.

The separate [network connectivity diagram](docs/diagrams/private-network.svg),
[editable network source](docs/diagrams/private-network.excalidraw) and
[animated private-network flow](docs/diagrams/github-gifs/PrivateNetworkFlow.gif)
show subnet, Private Endpoint, DNS and supporting outbound paths. See the
[diagram index](docs/diagrams/README.md#separate-network-connectivity-view) for
topology evidence, limitations and local regeneration.

| Component | Purpose |
| --- | --- |
| [Microsoft Entra ID](https://learn.microsoft.com/entra/identity-platform/) | SPA/API authentication, delegated scope and Caseworker/Reviewer roles. |
| [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/) | First-choice private frontend, API and continuously running extraction worker. |
| [Azure Kubernetes Service](https://learn.microsoft.com/azure/aks/) | Conditional private FIPS/Istio hosting fallback when approved requirements demand it; not a second simultaneous runtime. |
| [Azure Blob Storage](https://learn.microsoft.com/azure/storage/blobs/) | Separate original PDFs, durable review state, approved PDF copies and human-validated field JSON. |
| [Azure AI Content Understanding](https://learn.microsoft.com/azure/ai-services/content-understanding/) | Application-called custom analyzer for structured extraction, confidence and evidence. |
| [Azure AI Search](https://learn.microsoft.com/azure/search/) | Two private indexers: native CU layout for approved PDFs and JSON indexing for corrected fields; shared case/owner-filterable evidence index and Foundry IQ knowledge retrieval. |
| [Microsoft Foundry Agent Service](https://learn.microsoft.com/azure/ai-foundry/agents/overview) | Existing managed prompt agent and approved model deployments; dedicated native Blob/Cosmos stores remain separate from application storage. |
| [Azure Container Registry](https://learn.microsoft.com/azure/container-registry/) | Private ACR Tasks builds on a VNet-connected agent pool and immutable-digest runtime images; no local Docker daemon. |
| [Terraform](https://developer.hashicorp.com/terraform/docs) | Approved platform, knowledge, hosting and runtime stages with distinct secured private/keyless backend keys. |
| [Bicep](infra/bicep/README.md) | Standalone native deployment alternative for a new solution, with ordered ARM, Graph and Search/CU operator stages. Not a second owner of today's Terraform-managed assets. |

**Target architecture, not a readiness or certification claim.** Private synthetic agent invocation, extraction, indexing, retrieval and portal access require live acceptance checks. Private networking and FIPS node flags alone do not prove cryptographic compliance.

## Before you begin

Existing private Foundry, Search, Storage, networking, model defaults and a prompt agent are prerequisites. Their state owners remain authoritative; this deployment reads them rather than importing or replacing them. The scenario creates its own application infrastructure and knowledge resources, not native service-generated containers or databases.

For this PoC, provision a **new private foundation**, not resources belonging to another project. Do not reuse, import, modify or peer with unrelated infrastructure. In the Terraform path, the connectivity root owns the new PoC network and administration VM; [`infra/foundation/`](infra/foundation/README.md) separately stages the private AI services, models, project, scoped AAD connections/grants, native capability host and discovered runtime bindings. Content Understanding defaults and prompt-agent bootstrap are separate private data-plane steps. Only after verification does the scenario root read these prerequisites without adopting their state. The [standalone Bicep path](docs/bicep-deployment.md) creates its own initial prerequisites without Terraform or a state backend.

Use one approved private-network-connected execution checkout, an explicitly approved supported region and, for Terraform, secured remote state. Administrators own application registrations, role assignments, private-link approvals, certificates and immutable retention. Confirm model/SKU availability and the selected processing boundaries separately for custom CU, native Search layout and agent inference.

For new browser registrations, the optional `infra/browser-identity/` Terraform
stage owns only a single-tenant SPA/API and its custom delegated scope/application
roles in a distinct secured backend. Administrator authority is still required;
it grants no directory role, Graph permission, client secret or tenant-wide consent.

Use a region and model SKU permitted by the deployment's validation rules, not Global SKUs. Resource location alone does not establish processing residency; verify the selected regional or Data Zone processing boundary. Global Azure control-plane services, Entra ID and Private DNS are not region-pinned. Tailscale is limited to explicitly approved synthetic-only PoC administration and is not FIPS-validated. For Terraform, only the connectivity and state-backend roots may use their separately approved owner-only local bootstrap state; foundation/scenario/build roots require secured remote state. Backend creation, scoped access grants, exact-hostname split DNS and existing-state migrations require explicit approvals.

**Published source is not proof of deployment readiness or FIPS certification.** The hard FIPS requirement covers **FIPS 140-3 encryption at rest and in transit**, not certification of the whole application, hashing or JWT validation. The Dockerfile requires an approved .NET 10 image by immutable digest; evidence must cover its TLS encryption and actual platform/service/transport encryption paths. Private connectivity, retention, identity and synthetic acceptance remain separate requirements before real documents are processed.

## Deploy the solution

Encryption attestations default to fail-closed `runtime_attestation_mode = "evidence_gated"`.
Only explicit user authorization for a **synthetic-only PoC** permits
`"synthetic_poc_attestation_deferred"`, with `compliance.approved = false` and
all three encryption evidence references exactly empty. Bicep uses equivalent
`runtime.attestation_mode`. Outputs label this **deferred/not certified**, never
production-ready. [The canonical exception](docs/highly-regulated-scenario.md#explicit-synthetic-poc-attestation-deferral)
preserves private endpoints/no public app/data ingress, encryption controls, approved processing boundaries,
real SPA/API authorization, knowledge, immutable images and human review.
Each exact deployment plan still needs separate approval.

No public inbound app/data endpoint or `publicIPAddress` assigned to the app or
its ingress gateway is permitted. Explicitly approved controlled outbound-only
NAT is acceptable and does not expose unsolicited inbound access; it is not a
deployment blocker or approval for unrestricted Internet egress. Preserve private
DNS, disabled public network access, registry admin disabled and bypass `None`.
See the [canonical networking distinction](docs/highly-regulated-scenario.md#literal-container-apps-private-endpoint-ingress);
a literal zero-public-IP inventory is a separate optional stricter architecture.

Start with [getting started](docs/getting-started.md) and follow the [scenario tutorial](docs/highly-regulated-scenario.md) for prerequisites, approved plans and acceptance checks. In Copilot App or CLI, tell Copilot **"Deploy the platform."** The workflow targets this private review scenario, not the legacy Fabric baseline.

1. Configure the chosen execution host and distinct secured backend keys without duplicating existing deployment state.
2. Review and approve the Terraform platform plan with hosting/runtime deferred and browser identity null if registrations are pending, then the knowledge plan after required private-link approvals.
3. Build through private ACR Tasks using an approved VNet-connected agent pool and base-image digest. The optional build-pool root owns only a new pool; ordinary public workers cannot build against the private registry.
4. Review hosting dependency egress and approve its separate provisioning plan, then accept the exact browser identity/cryptographic evidence (or explicitly authorize synthetic-only attestation deferral) and approve the immutable-digest runtime plan.
5. Complete synthetic identity, network, extraction, human-review, indexing, case-isolation, recovery and cryptographic acceptance checks.

Each saved Terraform plan requires approval before apply. A successful apply does not establish service readiness.

[Standalone Bicep source](infra/bicep/README.md) and its [native runbook](docs/bicep-deployment.md) are available for a separately authorized new solution without Terraform prerequisites. A fresh end-to-end Bicep recreation has not been demonstrated. Terraform remains the current live deployment owner; switching ownership requires migration review, not deployment over existing assets.

## Repository layout

| Component | Location |
| --- | --- |
| Review UI/API and extraction worker | `app/ReviewPortal/` |
| Synthetic application tests | `app/ReviewPortal.Tests/` |
| New PoC network and private Tailscale administration VM | [`infra/connectivity/`](infra/connectivity/README.md) |
| Private keyless Terraform backend bootstrap | [`infra/state-backend/`](infra/state-backend/README.md) |
| Staged private Foundry/Search/agent-data foundation | [`infra/foundation/`](infra/foundation/README.md) |
| Tools-disabled prompt-agent baseline and current native scope/security rollout | [`agents/exempt-agent/definition.json`](agents/exempt-agent/definition.json), [foundation instructions](infra/foundation/README.md#native-stages) |
| Scenario infrastructure and knowledge registration | `infra/highly-regulated/` |
| Optional private ACR task agent pool | `infra/acr-build/` |
| Standalone Bicep infrastructure, native stages, examples and offline checks | [`infra/bicep/`](infra/bicep/README.md) |
| Staged deployment and acceptance checks | [Scenario tutorial](docs/highly-regulated-scenario.md) |
| Local development and execution-host guidance | [Developer setup](docs/development.md) |

The inherited `workspace/`, `cicd/`, legacy `infra/*.tf` and Fabric-specific helpers are retained as upstream reference material. Do not initialize or apply that root, connect Fabric Git or execute its notebooks as part of this application deployment.
