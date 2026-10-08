# Highly regulated private IQ proof of concept

A private document-review application on Azure, derived from [the upstream IQ template](https://github.com/dcasati/private-iq-template).

## Target audience

This proof of concept is for teams designing human-led document review in highly regulated environments. The scenario assists reviewers of Form 3500 exemption applications using manually exported PDF packages; the extraction schema is configurable rather than a bundled Form 3500-specific model.

Caseworkers upload original PDFs through an Entra-authenticated private portal. Azure AI Content Understanding extracts structured fields, confidence and source evidence. Reviewers inspect the original, correct the extraction and explicitly confirm every field before the application publishes evidence for indexing.

Reviewers can then ask questions about their selected case. The API enforces both case and owner filters, checks retrieved references and supplies the evidence and corrected fields to an existing Foundry prompt agent with all tools disabled. Answers include source references. **Human judgment remains authoritative:** the application has no business-system connectors and never makes eligibility decisions.

## Components of this solution

![Target Azure architecture for private document review, showing human validation, private evidence indexing, case-scoped retrieval and separate build and native-agent storage boundaries.](docs/diagrams/private-document-review.svg)

[View the full-size architecture](docs/diagrams/private-document-review.svg). The [scenario tutorial](docs/highly-regulated-scenario.md#architecture-and-ownership) explains the flows and ownership boundaries.

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
| [Terraform](https://developer.hashicorp.com/terraform/docs) | Approved platform, knowledge and runtime stages with distinct secured private/keyless backend keys. |

**Target architecture, not a readiness or certification claim.** Private synthetic agent invocation, extraction, indexing, retrieval and portal access require live acceptance checks. Private networking and FIPS node flags alone do not prove cryptographic compliance.

## Before you begin

Existing private Foundry, Search, Storage, networking, model defaults and a prompt agent are prerequisites. Their state owners remain authoritative; this deployment reads them rather than importing or replacing them. The scenario creates its own application infrastructure and knowledge resources, not native service-generated containers or databases.

Use one approved private-network-connected execution checkout, an explicit region and secured remote state. Administrators own application registrations, role assignments, private-link approvals, certificates and immutable retention. Confirm model availability and the applicable US processing boundaries separately for custom CU, native Search layout and agent inference.

**No live deployment or FIPS certification is bundled.** The Dockerfile requires an organization-approved .NET 10 runtime image by immutable digest. Exact platform, image and transport evidence, private connectivity, retention, identity and synthetic acceptance checks must be approved and demonstrated before real documents are processed.

## Deploy the solution

Start with [getting started](docs/getting-started.md) and follow the [scenario tutorial](docs/highly-regulated-scenario.md) for prerequisites, approved plans and acceptance checks. In Copilot App or CLI, tell Copilot **"Deploy the platform."** The workflow targets this private review scenario, not the legacy Fabric baseline.

1. Configure the chosen execution host and distinct secured backend keys without duplicating existing deployment state.
2. Review and approve the Terraform platform plan, then the knowledge plan after required private-link approvals.
3. Build through private ACR Tasks using an approved VNet-connected agent pool and base-image digest. The optional build-pool root owns only a new pool; ordinary public workers cannot build against the private registry.
4. Accept the exact cryptographic evidence and approve the immutable-digest runtime plan.
5. Complete synthetic identity, network, extraction, human-review, indexing, case-isolation, recovery and cryptographic acceptance checks.

Each saved Terraform plan requires approval before apply. A successful apply does not establish service readiness.

## Repository layout

| Component | Location |
| --- | --- |
| Review UI/API and extraction worker | `app/ReviewPortal/` |
| Synthetic application tests | `app/ReviewPortal.Tests/` |
| Scenario infrastructure and knowledge registration | `infra/highly-regulated/` |
| Optional private ACR task agent pool | `infra/acr-build/` |
| Local development and execution-host guidance | [Developer setup](docs/development.md) |

The inherited `workspace/`, `cicd/`, legacy `infra/*.tf` and Fabric-specific helpers are retained as upstream reference material. Do not initialize or apply that root, connect Fabric Git or execute its notebooks as part of this application deployment.
