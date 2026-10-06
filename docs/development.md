# Developer setup and Copilot

The [scenario tutorial](highly-regulated-scenario.md) is the canonical private deployment guide. This derived project's **"Deploy the platform"** workflow targets `infra/highly-regulated/` and optional `infra/acr-build/`, not the inherited Fabric baseline.

## Select one execution host

The included devcontainer supplies Azure CLI, Terraform, Git/GitHub CLI, Copilot CLI, Python and Node. Install an approved .NET 10 SDK on the development host before running the application tests; the ACR build uses the Dockerfile's SDK stage and requires no local Docker daemon.

A normal Codespace is **not automatically connected to the private Azure VNet**. Use an organization-approved connected deployment host, or a Codespace with explicitly verified private connectivity. The runner needs the appropriate private service/DNS access for Terraform data-plane registration. The ACR agent pool separately needs private registry access and approved dependency egress.

For App-driven Codespaces work, select the exact Codespace using `gh codespace list --repo OWNER/REPO`, then use authenticated `gh codespace ssh` for all configuration edits, credentials, Terraform and checks in that checkout. Do not mix remote state with a local App worktree. Do not publish an SSH port, disable host verification or copy credentials into SSH arguments.

For local deployment, explicitly select the authoritative existing checkout and secured backend. Establish a new state owner only when the user intentionally starts a new deployment. Do not infer this from absent ignored files.

## Authenticate separately

Use the organization's approved Azure user/service identity and selected subscription through standard CLI/provider conventions. Resolve any `ARM_*` overrides before provisioning without printing secrets. Do not sign in, grant consent, create app registrations or assign access automatically.

Search and Content Understanding data-plane provider tokens are ephemeral inputs acquired inside each plan/apply shell, as documented in the tutorial. Never persist them in tfvars, state, profiles or logs. The application runtime uses managed/workload identity, not the deployment user's credential.

No Fabric PAT or Fabric capacity administrator is needed for this application workflow. Do not run the inherited Fabric configuration helpers to create scenario configuration.

## Configure and deploy

Tell Copilot **"Deploy the platform."** It loads the project-specific [deployment skill](../.github/skills/deploy-platform/SKILL.md), confirms the source/host/backend, inventories the existing private foundation and coordinates approved platform, knowledge, optional build-pool and runtime stages. Missing prerequisites are blockers, not permission to replace existing infrastructure.

The configuration-only [initialization skill](../.github/skills/initialize-project/SKILL.md) prepares local scenario inputs without cloud mutations. Use [template maintenance](../.github/skills/template-maintenance/SKILL.md) for static checks only.

## Local checks

Use the [tutorial's synthetic checks](highly-regulated-scenario.md#local-development-and-static-checks). Application tests mock cloud responses; Terraform static checks are `init -backend=false`, `fmt -check` and `validate` in each separate root. Use an isolated source-only copy if deployment files/state are present. Do not run a live plan, apply, indexer, analyzer or notebook as a maintenance check.

Keep original documents, real development configuration, credentials, build output, saved plans and state outside Git. Preserve stable inherited workspace logical IDs; their reference files are not part of this deployment.
