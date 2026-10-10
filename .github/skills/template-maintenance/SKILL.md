---
name: template-maintenance
description: Maintain and statically validate the Fabric and Foundry repository template, including Terraform, the devcontainer, onboarding scripts and Copilot guidance. Use for template changes or local checks without live Azure/Fabric deployment or notebook execution.
---

# Maintain the template

Read `AGENTS.md` and inspect the current diff before editing. Preserve unrelated changes and staging. Treat ignored configuration/state as user-owned; inspect filenames, not contents.

## Locate the relevant contract

| Change | Read before editing |
| --- | --- |
| Resource naming, tags or inputs | `infra/main.tf`, `infra/variables.tf`, `infra/terraform.tfvars.example` |
| Capacity, Git credentials or deployment pipeline | `infra/fabric.tf`, `infra/providers.tf`, `cicd/README.md` |
| Foundry or knowledge retrieval | `infra/foundry.tf`, `infra/knowledge.tf`, `infra/outputs.tf`, `docs/ontology-knowledge.md` |
| Workspace definitions or notebooks | The `fabric-workspace` skill and its linked guides |
| Developer tools or initialization | `.devcontainer/`, the `initialize-project` skill and `docs/development.md` |
| Guided private application deployment | The `deploy-platform` skill, `docs/getting-started.md` and `docs/highly-regulated-scenario.md`; use `docs/bicep-deployment.md` only for a separately authorized new Bicep-owned solution |
| Inherited Fabric deployment reference | `cicd/README.md` and `deploy-platform/references/native-requests.md`; neither belongs to the private application workflow |
| Highly regulated review application or private ACR build pool | `docs/highly-regulated-scenario.md`, `app/`, and the separate `infra/highly-regulated/` and `infra/acr-build/` roots; preserve the base infrastructure/initializer contract |

Preserve the non-obvious infrastructure constraints:

- Create capacity before looking up its Fabric GUID; workspaces cannot use its Azure resource ID.
- Keep Git connection/initialization/sync outside Terraform: the pinned provider cannot attach a deployment plan. Keep GitHub integration, empty TEST, and administrator-owned tenant settings.
- Use `Microsoft.CognitiveServices/accounts` projects, not ML hubs. Keep model versions/SKUs/quota configurable.
- Manage Search sources/bases through data-plane `restful_resource`, not unsupported ARM types. Retain CRUD and drift detection, source rebuild triggers, and knowledge-base-before-source deletion ordering. The OneLake source owns its generated search assets.
- Look up Git-owned items rather than creating duplicate lakehouses/notebooks in Terraform. Keep DEV-only Search permissions and conditional knowledge resources when the lakehouse ID is null.
- Keep deployment-pipeline replacement semantics visible when changing stages. Do not hide drift or paper over unsupported provider behavior.

## Run static checks only

For an unconfigured checkout, run from `infra/`:

```sh
terraform init -backend=false -input=false -lockfile=readonly
terraform fmt -check -recursive
terraform validate
```

If local deployment files exist, make an isolated temporary configuration directory. Copy **only tracked `infra/*.tf` files and `infra/.terraform.lock.hcl`**, using their current working-tree contents so edits are included. Do not copy tfvars, state, overrides, saved plans, `.terraform/`, credentials or logs. Run the same commands there. Do not use `git archive HEAD` to validate uncommitted edits. Clean up only the temporary files you created.

Do not upgrade providers during unrelated maintenance; retain the lock file. An intentional provider update requires updating constraints and reviewing the lock change separately. A static-check failure is not permission to use `plan`, `apply`, `destroy` or a live Fabric operation.

For `infra/highly-regulated/` and optional `infra/acr-build/`, run the same static checks in each separate root with its own lock file; do not run the Fabric initializer. Run the application tests with `dotnet test app/ReviewPortal.Tests/ReviewPortal.Tests.csproj` and parse the browser scripts with `node --check`. These tests use synthetic identities and mocked cloud responses, not real documents, service execution or cryptographic certification. An image build requires an explicitly approved runtime image; never substitute a standard image and describe it as FIPS validated.

For changed Python, parse/compile source without executing notebook cells; Fabric supplies NotebookUtils, Spark and Delta. Exercise initializer behavior in a **temporary fixture repository**, not by creating deployment config in this template: valid inputs, a non-main branch, repeated execution, existing tfvars/state, invalid inputs and literal HCL escaping. Check the generated shape and owner-only permissions.

For the knowledge configuration helper, verify the two-field change, repeatability, preservation of unrelated settings, rejection of zero/logical/conflicting IDs and custom registrations, and no cloud calls. Validate deployment-skill request shapes against the documented APIs; do not execute its live command examples as a template test.

For devcontainer changes, validate the configuration against the Dev Container schema and inspect feature options against their published definitions. If Docker is available, build/start an isolated checkout without local credentials/state, run `.devcontainer/check-tools.sh`, then stop/remove only that test container. A container check must not sign in, initialize Terraform, seed or deploy.

## Keep the experience small

Keep always-applicable rules in `AGENTS.md`, task procedures in `.github/skills/<name>/SKILL.md`, and explanations in the canonical docs. Use skill metadata with a clear trigger; do not require developers to install the same skill globally or duplicate root instructions in App settings.

Keep base-image, Terraform and Copilot pins compatible with their documented requirements. Install the official Copilot release with mandatory checksum verification during image build; keep startup free of installs and cloud operations. Node 24 supports Node-based developer/MCP tools. Do not add Fabric CLI, fabric-cicd, local Spark or Azure deployment wrappers just to validate the template.

Keep Codespaces SSH private and managed through `gh codespace ssh`; do not publish its port, set passwords or disable host verification. App-driven deployment must route both commands and file changes to the same remote checkout/state.

Update README, getting started and the safe tfvars example when inputs or behavior change. Preserve the initializer's exact placeholder contract when editing the example. Do not bundle project-specific Terraform/deployment test suites or claim that static checks verify cloud permissions, preview availability, quota or ingestion.
