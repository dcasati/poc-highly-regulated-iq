# Highly regulated private IQ proof of concept

A private document-review application derived from [the upstream IQ template](https://github.com/dcasati/private-iq-template). Users upload exported PDF packages, validate Content Understanding extractions and ask case-scoped questions through an existing Foundry prompt agent. Human judgment remains authoritative; the application has no business-system connectors or automated eligibility decisions.

| Component | Location |
| --- | --- |
| Entra-authenticated review UI/API and extraction worker | `app/ReviewPortal/` |
| Synthetic application tests | `app/ReviewPortal.Tests/` |
| New US-only PoC network and private Tailscale administration VM | [`infra/connectivity/`](infra/connectivity/README.md) |
| Scenario infrastructure and knowledge registration | `infra/highly-regulated/` |
| Optional private ACR task agent pool | `infra/acr-build/` |
| Staged deployment and acceptance checks | [Scenario tutorial](docs/highly-regulated-scenario.md) |

## Deploy

Start with [getting started](docs/getting-started.md), choose one approved private-network-connected execution checkout and secured backend, and tell Copilot **"Deploy the platform."** The repository workflow targets the private review scenario, not the legacy Fabric baseline. Each Terraform plan needs approval before its saved apply.

This PoC requires a **new US-only foundation**, not resources belonging to another project. Do not reuse, import, modify or peer with unrelated infrastructure. The connectivity root creates only the new PoC network and administration VM; the US AI foundation still needs its own reviewed implementation and provisioning. Once created, private Foundry, Search S1 or higher, Storage, model defaults and a prompt agent are prerequisites read by the scenario root without adoption into its state. Container Apps is evaluated first, with a private AKS/FIPS/Istio fallback when the approved constraints require it.

All regional resources and AI processing must remain in the United States; a US account location alone is insufficient. Use approved US regional/Data Zone models, not Global SKUs. Global Azure control-plane services, Entra ID and Private DNS are not region-pinned. Tailscale is limited to explicitly approved synthetic-only PoC administration and is not FIPS-validated. Only the connectivity root may use explicitly approved owner-only local bootstrap state; later roots require secured remote state.

ACR Tasks builds the application without a local Docker daemon using an approved VNet-connected agent pool. A private registry with public access disabled cannot use ordinary public build workers. The optional build-pool root owns only the new pool and requires separate secured state.

**No live deployment or FIPS certification is bundled.** The Dockerfile requires an organization-approved .NET 10 runtime image by immutable digest. Platform, image and transport evidence, private connectivity, retention, identity and synthetic acceptance checks must be approved and demonstrated before real documents are processed.

The inherited `workspace/`, `cicd/`, legacy `infra/*.tf` and Fabric-specific helpers are retained as upstream reference material. Do not initialize or apply that root, connect Fabric Git or execute its notebooks as part of this application deployment.
