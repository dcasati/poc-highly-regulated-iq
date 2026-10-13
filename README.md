# PoC: Highly regulated private IQ

An Azure proof of concept for human-led review of manually exported PDF application packages. **Synthetic documents only.** Caseworkers upload documents through a private, Entra-authenticated portal. Content Understanding proposes fields, confidence and source evidence. This PoC supports owner self-review: users assigned both Caseworker and Reviewer roles correct and confirm every field before publication.

For case-scoped questions, the API supplies case-authorized evidence and validates citation IDs. Answers remain suggestions requiring source verification. **People make the decisions:** there are no business-system connectors or automated eligibility decisions.

## Architecture

![Private document review: intake, human review, approved evidence and case-scoped answers.](docs/diagrams/private-document-review.svg)

![Private network connectivity: private access, Private Endpoints, DNS and one shared outbound-only NAT.](docs/diagrams/private-network.svg)

| Component | Purpose |
| --- | --- |
| Microsoft Entra ID | Single-tenant SPA/API authentication, delegated scope and Caseworker/Reviewer roles. |
| Azure Container Apps | Private portal, API and continuously running extraction worker. |
| Blob Storage | Dedicated containers for originals, review state, approved PDFs and corrected field evidence. |
| Content Understanding | Configurable extraction schema, confidence and source references. |
| Azure AI Search / Foundry IQ | Private indexing and retrieval of human-approved evidence. |
| Azure OpenAI | Direct private chat completion with API-supplied case evidence and validated citation IDs; no tools. |
| Azure Container Registry | Private builds and immutable-digest runtime images. |
| Bicep + Azure CLI | Modular infrastructure and explicit native service/identity handoffs. |

## Get started

Follow [getting started](docs/getting-started.md), the canonical deployment guide. `infra/bicep/` is the infrastructure source; `run.sh` is a small Bash entry point:

```bash
./run.sh -x check-deps
./run.sh -x build
# After choosing the target and creating reviewed local parameters:
PARAMETERS_FILE=infra/bicep/examples/main.local.bicepparam \
  LOCATION="$APPROVED_REGION" ./run.sh -x what-if
```

Installation requires approval of the exact target and changes. The script does not grant Microsoft Graph permissions, register native data-plane objects or silently adopt existing resources. In Copilot App/CLI, **"Deploy the platform"** follows the same guide.

Use a **new private PoC foundation**, an explicitly approved supported region and one approved private-network-connected execution host. Do not reuse or modify another project's infrastructure. App/data ingress uses Private Endpoints only, with public network access disabled. A separately approved controlled outbound NAT public IP is allowed; it does not expose inbound access or permit unrestricted egress.

This PoC uses the approved synthetic-only attestation-deferred runtime mode. See the [scenario constraints](docs/highly-regulated-scenario.md#synthetic-only-poc) for its parameter contract and required controls.

The portal, API and worker share one process, identity and replica, so they are not privilege-separated. See the [trust-boundary limitations](docs/highly-regulated-scenario.md#authentication).

## Steps to run this demo

Clone the repo first; the commands below use relative paths.

1. Clone and enter the repo:

    ```bash
    git clone https://github.com/dcasati/poc-highly-regulated-iq
    cd poc-highly-regulated-iq
    ```

2. Install and sign in to `az` (with Bicep) and `jq`, then check them:

    ```bash
    az login
    ./run.sh -x check-deps
    ```

3. Copy each sanitized example in `infra/bicep/examples/` to an ignored `<stage>.local.bicepparam` (for example `main.example.bicepparam` to `main.local.bicepparam`), then set your project name, an approved region, the admin user and the model deployments. Never commit local files.

4. Check the template, then preview and approve the changes before installing:

    ```bash
    ./run.sh -x build
    export PARAMETERS_FILE=infra/bicep/examples/main.local.bicepparam LOCATION=westus3
    ./run.sh -x what-if
    ./run.sh -x install   # prints what-if, then requires a typed "yes"
    ```

5. Follow [getting started](docs/getting-started.md) for the remaining stages, in order: platform and private links, private image build, Container Apps runtime, Entra app registrations, Content Understanding defaults and Search objects. Each stage has its own what-if and approval.

6. Reach the private portal from an approved private-network host (or your approved admin tunnel). Add a hosts entry or exact-hostname split DNS that maps the portal hostname to its Private Endpoint IP, then open the portal URL.

7. Run the synthetic flow: sign in, upload one synthetic PDF, confirm every extracted field, publish as Reviewer, run both Search indexers, then ask a case-scoped question.

Review the temporary operator role grants after setup; see [Rights granted](docs/getting-started.md#rights-granted). Removing a grant needs separate approval.

## Repository

| Location | Contents |
| --- | --- |
| [`infra/bicep/`](infra/bicep/README.md) | Subscription entry point, focused modules and sanitized parameter examples. |
| `run.sh` | `check-deps`, `build`, `what-if`, `install`, `show`; native Azure CLI deployment commands. |
| `app/ReviewPortal/` | Portal/API and extraction worker. |
| `app/ReviewPortal.Tests/` | Local application checks with synthetic inputs/mocked services. |
| [Scenario](docs/highly-regulated-scenario.md) | Application flows, authorization and synthetic-use constraints. |
| [Development](docs/development.md) | Local tools and execution-host guidance. |
