---
name: initialize-project
description: Configure local inputs for this derived private document-review IQ project without deployment. Choose branding, an explicit region and verified existing-resource/network/identity references. Never run the inherited Fabric initializer for this scenario.
---

# Configure the private review scenario

Read `AGENTS.md`, `docs/getting-started.md`, `docs/development.md`, `docs/highly-regulated-scenario.md` and the sanitized examples in `infra/highly-regulated/` and optional `infra/acr-build/`.

If the user requested deployment, let `deploy-platform` coordinate the complete workflow. Configuration alone is not deployment.

## Establish the chosen host and target

Confirm the derived repository and its published reviewed branch/commit. Reuse the execution checkout, subscription and backend choices already provided. Inspect filenames only for existing tfvars/backend/state; do not infer a new state owner from missing files in an App worktree. If configuration exists, preserve it and ask before conflicting changes.

Ask only for missing inputs, one at a time: a generic 3-16 character project name, explicit approved region, verified existing Foundry/project/agent/Search/Storage/network references, approved subnets and administrator-approved SPA/API registration metadata. Do not truncate the repository name into branding, guess physical IDs, select a cloud region silently or ask for secrets.

The existing private foundation must satisfy the tutorial's service, identity, model-default and shared-link prerequisites. Do not provision or import it as a side effect of initialization.

## Create local configuration only

On the chosen execution host, create one owner-only ignored `infra/highly-regulated/terraform.tfvars` from its sanitized example only when the file does not already exist. Fill approved nonsecret inputs. A genuinely new deployment starts with `provision_hosting = false`, `deploy_knowledge = false`, `deploy_runtime = false`, `image_digest = null` and compliance unapproved. Never reset these values on resume.

If a new private ACR pool is required, prepare the separate build-root tfvars from its example without adopting another project's pool. Keep preview approval false until the authorized organization accepts it. Keep backend keys separate and credentials outside tfvars; backend provisioning/migration is not initialization.

Verify local configuration is ignored without printing it. Search/Content Understanding tokens are ephemeral provider inputs acquired later inside each plan/apply shell; never write them into files.

Do not run `scripts/initialize_project.py`, request Fabric capacity administrators/PATs, execute Terraform plans/applies or change cloud access during this step. The inherited script configures a different Fabric baseline.

Return the configuration status and unresolved prerequisites to `deploy-platform`. Preserve all inherited workspace logical IDs and reference definitions.
