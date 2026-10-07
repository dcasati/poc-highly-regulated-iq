---
name: deploy-platform
description: Deploy or resume this derived private document-review IQ proof of concept. Use for "deploy the platform" or "deploy this project". Coordinate existing-private-resource preflight, approved Terraform stages, a VNet-connected ACR build, cryptographic gates and synthetic readiness checks. Do not deploy the inherited Fabric baseline.
---

# Deploy the private document-review platform

Read `AGENTS.md`, `docs/getting-started.md`, `docs/development.md` and `docs/highly-regulated-scenario.md`. Treat the request as the complete private application setup, not just a Terraform apply. Require an actual user deployment request, reuse confirmed choices and ask only for missing inputs, one at a time. Never ask for secrets in chat.

## 1. Confirm one source, execution host and state owner

Use this derived repository's published reviewed commit. Do not deploy unpushed changes, the upstream reusable template, or a new App worktree with missing ignored configuration. Select one approved private-network-connected execution checkout and retain it for all edits, authentication, plans, applies and checks.

This PoC requires a new US-only foundation. Other projects' resources are excluded: do not read, reuse, import, peer with or modify them. Do not carry a previously selected unrelated registry/VNet into this deployment. Validate regional service support and approved US regional/Data Zone models; Global deployment SKUs are not acceptable.

For App-driven Codespaces, list candidates with `gh codespace list --repo OWNER/REPO --json name,repository,state,gitStatus`, have the user choose the exact host, and route all work through authenticated `gh codespace ssh`. Verify the remote repository, commit and checkout path. A normal Codespace does not imply VNet connectivity. Never bypass SSH host verification or expose an SSH port.

For an explicitly chosen local host, use its authoritative checkout/backend. If this is a genuinely new deployment, confirm that decision and establish secured remote state before provisioning. Give `infra/highly-regulated/` and optional `infra/acr-build/` distinct backend keys. Do not create a backend, migrate state, force-unlock or discard state automatically.

The explicit connectivity bootstrap exception permits `infra/connectivity/` to use owner-only local state on the encrypted authoritative Mac. This root creates only the new US VNet/private synthetic-only administration VM and associated egress, not the AI foundation. Review/apply its exact saved plan only after approval; verify cloud-init before separately approved operator enrollment, tailnet route/ACL approval and split DNS. Tailscale is not FIPS-validated.

The separately approved `infra/state-backend/` bootstrap exception permits temporary owner-only local state for this root on that same encrypted host. It provisions a new private/keyless US Blob backend, reserved endpoint subnet and PoC Blob private DNS; inspect the current deployment-identity container grant in its separately approved saved plan. Verify actual private networking, versioning/retention, keyless authorization and exact-hostname split DNS before migration. In a shared tailnet, do not override unrelated projects' global Azure service domains. Obtain separate approval for each existing state's exact source/target/key, migrate natively, verify lineage/serial and a no-change plan, and retain local backups until cleanup is authorized. Foundation/scenario/build roots require secured remote state; no other local-state exception is implied.

## 2. Inventory the existing private foundation

Here "existing" means the new PoC's foundation after its own reviewed Terraform implementation and provisioning, not another project. If it is absent, prepare/review that US-only foundation first and stop scenario applies until its identities, DNS, model defaults and private links are verified. Do not treat the connectivity VM as an AI deployment.

Use `initialize-project` for configuration only on the chosen host. Preserve existing ignored configuration and do not dump tfvars/state/environment values. Check the effective subscription/directory and provider overrides without printing credentials.

Verify the existing private Foundry account/project/prompt agent, Search S1 or higher and system identity, Blob Storage, VNet/subnets, private DNS, model defaults and service-role prerequisites documented in the tutorial. Verify physical resource identities rather than names alone. Do not recreate or import the existing foundation into this project's state.

Administrators own consent, SPA/API registrations and user roles, certificates, locked retention, provider registration and target-owner private-link approvals. Stop for missing access, quota, networking or approval. Container Apps is the first hosting choice; use AKS only after its requirement is established. Confirm the exact runtime image and platform/transport cryptographic evidence before deploying containers; neither private connectivity nor FIPS nodes prove certification.

Do not request a Fabric PAT, capacity administrator or Fabric consent, run the inherited Fabric initializer, apply the legacy `infra/` root, synchronize workspace items or execute notebooks.

## 3. Apply the reviewed platform stage

From `infra/highly-regulated/` on the chosen host, initialize the agreed backend without provider upgrades, validate and create a uniquely named saved plan with `-input=false`. For a new deployment keep `deploy_knowledge` and `deploy_runtime` false; on resume preserve the deployed flags and configuration rather than resetting them.

Acquire short-lived Search and Content Understanding tokens in each plan/apply shell as ephemeral provider inputs. Never print or persist them. Use native Terraform only, no AZD hooks or custom wrapper.

Summarize costs, preview/network exposure, permissions and replacements/deletions. Obtain approval for the exact saved plan before applying it. If source, inputs, state or target changes, create a new plan and obtain new approval. Do not use `-auto-approve`, targeted apply or broad replacement.

Verify platform provisioning and preserve state on partial failure. Do not delete successful resources to recover.

## 4. Complete knowledge registration

Have the existing owners approve the required processing/billing shared links. Verify approved states, group IDs and target resource identities, including the existing Blob link.

Enable `deploy_knowledge`, preserve runtime settings as appropriate, and review/apply a separately saved knowledge plan with fresh ephemeral tokens. Verify the custom analyzer, native layout skillset, two private indexers, controlled index, searchIndex knowledge source/base and nonshared operator project connection.

Do not claim that registration proves indexing, extraction or retrieval. Never expose the unfiltered connection as a caseworker tool.

## 5. Build the approved image in private ACR

Reuse an approved VNet-connected ACR agent pool if one exists. Otherwise configure `infra/acr-build/` against the selected existing private Premium registry and dedicated approved subnet, with its own secured backend key. Obtain preview/network approvals, verify region/quota/dependency egress and review/apply the exact saved build-pool plan.

Keep registry public access disabled. Do not enable public access, relax firewall rules or grant permissions to make a build succeed. The build pool's private connectivity is not FIPS evidence.

Inspect the application build context for credentials/configuration, then use the tutorial's `az acr build --agent-pool` command with the approved .NET 10 runtime image by immutable digest and a unique run tag. No local Docker daemon is needed. Treat a queued run as incomplete; observe its terminal status with a bounded deadline and require `Succeeded` plus the output digest.

The runtime root deploys from its own registry. If a different build registry was selected, request approval for the transfer and verify the destination digest before setting `image_digest`. Never assume an image is present in both registries.

## 6. Deploy and verify the runtime

Complete the exact platform/image/transport approval references, set `image_digest` and enable `deploy_runtime`. Review/apply a separately saved runtime plan. Preserve the current hosting choice; changing Container Apps to AKS is a migration needing separate review.

Verify runtime provisioning, private DNS/access, Entra redirect/roles, service identities and any AKS certificate/mesh prerequisites. A successful apply or health endpoint is not readiness.

Run only authorized synthetic documents through the tutorial's acceptance checks: retained originals/digests, custom extraction/confidence, explicit human gate, zero-failure native indexing, case/owner isolation, grounded existing-agent responses without tools, recovery, retention and cryptographic evidence. Observe asynchronous phases for a bounded deadline (30 minutes unless the user chooses another), honor Retry-After and retain operation/run identifiers for resume without persisting secrets.

Report completed and blocked stages, the chosen host/state owner and remaining approvals. Claim ready only after the acceptance checks pass. Do not fabricate certification, process real documents, promote to production or tear down resources without a separate request.
