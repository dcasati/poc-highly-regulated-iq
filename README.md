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

## Run the demo

[Getting started](docs/getting-started.md) is the canonical guide. Every infrastructure change needs a reviewed what-if and explicit approval.

1. Clone the repo, sign in with `az login`, then run `./run.sh -x check-deps` (needs `az` with Bicep, and `jq`).
2. Copy each `infra/bicep/examples/<stage>.example.bicepparam` to an ignored `<stage>.local.bicepparam` and set the project name, approved region, admin user and models.
3. Preview, then install:

    ```bash
    ./run.sh -x build
    export PARAMETERS_FILE=infra/bicep/examples/main.local.bicepparam LOCATION=<approved-region>
    ./run.sh -x what-if
    ./run.sh -x install   # shows what-if, then requires a typed "yes"
    ```

4. Complete the remaining stages in the guide: platform, private image build, runtime, Entra apps, Content Understanding and Search objects. These native handoffs are never automatic.
5. From a private-network host, map the portal hostname to its Private Endpoint IP (hosts entry or exact-hostname split DNS) and open the portal.
6. Sign in, upload one synthetic PDF, confirm every field, publish as Reviewer, run both Search indexers and ask a case-scoped question.

Use a new private PoC foundation, an approved region and Private Endpoints only; never reuse another project's resources. The runtime mode is synthetic-only ([constraints](docs/highly-regulated-scenario.md#synthetic-only-poc)). The portal, API and worker share one process and identity ([limitations](docs/highly-regulated-scenario.md#authentication)). Review temporary operator grants after setup ([Rights granted](docs/getting-started.md#rights-granted)).

## Repository

| Location | Contents |
| --- | --- |
| [`infra/bicep/`](infra/bicep/README.md) | Subscription entry point, focused modules and sanitized parameter examples. |
| `run.sh` | `check-deps`, `build`, `what-if`, `install`, `show`; native Azure CLI deployment commands. |
| `app/ReviewPortal/` | Portal/API and extraction worker. |
| `app/ReviewPortal.Tests/` | Local application checks with synthetic inputs/mocked services. |
| [Scenario](docs/highly-regulated-scenario.md) | Application flows, authorization and synthetic-use constraints. |
| [Development](docs/development.md) | Local tools and execution-host guidance. |
