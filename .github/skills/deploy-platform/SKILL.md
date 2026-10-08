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

For an explicitly chosen local host, use its authoritative checkout/backend. If this is a genuinely new deployment, confirm that decision and establish secured remote state before provisioning. Give `infra/highly-regulated/`, optional `infra/acr-build/` and optional `infra/browser-identity/` distinct backend keys. Do not create a backend, migrate state, force-unlock or discard state automatically.

If an isolated project CLI profile has been approved, set `AZURE_CONFIG_DIR` to its confirmed absolute path in every CLI/Terraform shell, along with the selected subscription. Reuse that profile and its existing protected sign-in cache; do not duplicate tokens, change shared CLI defaults or grant a different cached principal access. Verify native-backend authentication uses the approved deployment identity.

The explicit connectivity bootstrap exception permits `infra/connectivity/` to use owner-only local state on the encrypted authoritative Mac. This root creates only the new US VNet/private synthetic-only administration VM and associated egress, not the AI foundation. Review/apply its exact saved plan only after approval; verify cloud-init before separately approved operator enrollment, tailnet route/ACL approval and split DNS. Tailscale is not FIPS-validated.

The separately approved `infra/state-backend/` bootstrap exception permits temporary owner-only local state for this root on that same encrypted host. It provisions a new private/keyless US Blob backend, reserved endpoint subnet and PoC Blob private DNS; inspect the current deployment-identity container grant in its separately approved saved plan. Verify actual private networking, versioning/retention, keyless authorization and exact-hostname split DNS before migration. In a shared tailnet, do not override unrelated projects' global Azure service domains. Obtain separate approval for each existing state's exact source/target/key, migrate natively, verify lineage/serial and a no-change plan, and retain local backups until cleanup is authorized. Foundation/scenario/build roots require secured remote state; no other local-state exception is implied.

## 2. Inventory the existing private foundation

Here "existing" means the new PoC's foundation after its own reviewed Terraform implementation and provisioning, not another project. If it is absent, prepare/review `infra/foundation/` first and stop scenario applies until its identities, DNS, model defaults and private links are verified. Follow its staged account/dependencies/models, private connectivity, project, verified provisioning identity/connections, capability host and discovered runtime-bindings plans. Account/project/connection APIs use `2025-06-01`; creation-time network injection remains mandatory. The explicitly accepted `2025-04-01-preview` capability host references Terraform-owned AAD project connection names. Never duplicate native service-created containers/databases or copy the official sample's key-enabled/permissive-network defaults. Obtain separate plan approval for project bootstrap roles and verify their successful live assignments, exact principal/scopes and private connection targets before host creation. Management-plane visibility or a fixed sleep is not proof of managed-service authorization propagation; the native host create is the next service-side check, not permission to broaden access after a failure. Review the bootstrap Blob-grant revocation when runtime container roles replace it. Bootstrap Content Understanding defaults and the prompt agent over verified private endpoints without provisioners. Review runtime/build dependency egress before scenario environment or pool provisioning. Do not treat the connectivity VM as an AI deployment.

Use `initialize-project` for configuration only on the chosen host. Preserve existing ignored configuration and do not dump tfvars/state/environment values. Check the effective subscription/directory and provider overrides without printing credentials.

Verify the existing private Foundry account/project/prompt agent, Search S1 or higher and system identity, Blob Storage, VNet/subnets, private DNS, model defaults and service-role prerequisites documented in the tutorial. Verify physical resource identities rather than names alone. Do not recreate or import the existing foundation into this project's state.

Administrators own consent, SPA/API registrations and user roles, certificates, locked retention, provider registration and target-owner private-link approvals. Stop for missing access, quota, networking or approval. Container Apps is the first hosting choice; use AKS only after its requirement is established. The hard FIPS requirement is FIPS 140-3 encryption at rest/in transit, not whole-app/hash/JWT certification. Confirm the exact image TLS and platform/service/transport encryption evidence; neither algorithms, private connectivity nor FIPS nodes alone establish module validation.

An authorized administrator may separately review `infra/browser-identity/` for
new single-tenant registrations and explicitly approved current-user API roles.
Verify the selected directory, absent display names and distinct backend owner;
do not adopt existing identities or grant Graph/directory privileges. Add only
exact HTTPS redirects after discovering the private hosting domain. Registration
and preauthorization do not prove token issuance or browser/role readiness.

Do not request a Fabric PAT, capacity administrator or Fabric consent, run the inherited Fabric initializer, apply the legacy `infra/` root, synchronize workspace items or execute notebooks.

## 3. Apply the reviewed platform stage

From `infra/highly-regulated/` on the chosen host, initialize the agreed backend without provider upgrades, validate and create a uniquely named saved plan with `-input=false`. Both scenario and ACR-build roots declare the native azurerm backend; verify their distinct keys. For a new deployment keep `provision_hosting`, `deploy_knowledge` and `deploy_runtime` false; on resume preserve the deployed flags and configuration rather than resetting them. Initial platform preparation needs no browser registrations: use `identity = null`, never placeholder GUIDs. It creates private registry/data/managed-identity prerequisites, not a hosting environment or unauthenticated app. Review runtime dependency egress and a separate `provision_hosting = true` plan before creating the chosen environment or cluster.

Acquire short-lived Search and Content Understanding tokens in each plan/apply shell as ephemeral provider inputs. Never print or persist them. Use native Terraform only, no AZD hooks or custom wrapper.

Summarize costs, preview/network exposure, permissions and replacements/deletions. Obtain approval for the exact saved plan before applying it. If source, inputs, state or target changes, create a new plan and obtain new approval. Do not use `-auto-approve`, targeted apply or broad replacement.

A direct user chat reply approving the disclosed artifact is valid approval.
If an interactive prompt cannot collect an answer, an unavailable-user or autonomy
fallback is not approval. Keep preparation and read-only verification automatic;
do not treat blanket consent as approval of undisclosed future access/cost changes.

Verify platform provisioning and preserve state on partial failure. Do not delete successful resources to recover.

## 4. Complete knowledge registration

Have the existing owners approve the required processing/billing shared links. Verify approved states, group IDs and target resource identities, including the existing Blob link.

Enable `deploy_knowledge`, preserve runtime settings as appropriate, and review/apply a separately saved knowledge plan with fresh ephemeral tokens. Verify the custom analyzer, native layout skillset, two private indexers, controlled index, searchIndex knowledge source/base and nonshared operator project connection.

Do not claim that registration proves indexing, extraction or retrieval. Never expose the unfiltered connection as a caseworker tool.

## 5. Build the approved image in private ACR

Reuse an approved VNet-connected ACR agent pool if one exists. Otherwise configure `infra/acr-build/` against the selected existing private Premium registry and dedicated approved subnet, with its own secured backend key. Obtain preview/network approvals, verify region/quota/dependency egress and review/apply the exact saved build-pool plan.

Keep registry public access disabled. Do not enable public access, relax firewall rules or grant permissions to make a build succeed. The build pool's private connectivity is not FIPS evidence.

Inspect the application build context for credentials/configuration, then use the tutorial's `az acr build --agent-pool` command with the approved .NET 10 runtime image by immutable digest and a unique run tag. No local Docker daemon is needed. Treat a queued run as incomplete; observe its terminal status with a bounded deadline and require `Succeeded` plus the output digest.

For restricted package egress, use the documented offline feed and verify native
locked restore in a new cache before upload; do not replace NuGet content-hash
verification with raw signed-archive hashes or bypass rejected signature chains.
Candidate builds may gather evidence, but must not set runtime compliance approval.
After work completes, check the queue before any separately reviewed scale-to-zero
plan for this owned pool; preserve its image/state and never stop another build.
Verify a fresh full plan after scaling. The native ARM tags child owns pool tags
because pinned AzureRM omits tags on updates; review any tag-only repair rather
than ignore all drift or repeat ineffective AzureRM tag updates.

The runtime root deploys from its own registry. If a different build registry was selected, request approval for the transfer and verify the destination digest before setting `image_digest`. Never assume an image is present in both registries.

## 6. Deploy and verify the runtime

Default to `runtime_attestation_mode = "evidence_gated"`: complete `compliance.encryption_standard = "FIPS140-3"` and the exact platform/service, image TLS and transport encryption approval references plus real SPA/API identity. Do not gate on independent whole-app/hash/JWT certification. Only an explicit user request to defer attestations for synthetic PoC use authorizes `runtime_attestation_mode = "synthetic_poc_attestation_deferred"`; keep `compliance.approved = false` and all three evidence strings exactly empty. Bicep uses the equivalent `runtime.attestation_mode` typed branch with `approved: false` and empty encryption evidence; knowledge approval stays mandatory. Never fabricate evidence, certification or production readiness. Verify/report `runtime_attestation_status` as deferred/not certified. This defers evidence only, not encryption controls, private endpoints/no public IP, real SPA/API identity/roles, US processing, knowledge, human review or immutable digest. Set `image_digest` and enable `deploy_runtime` only after `provision_hosting` is enabled. Review/apply a separately saved runtime plan with exact user approval; attestation deferral is not saved-plan approval. Preserve the current hosting choice; changing Container Apps to AKS is a migration needing separate review.

Verify runtime provisioning, private DNS/access, Entra redirect/roles, service identities and any AKS certificate/mesh prerequisites. A successful apply or health endpoint is not readiness.

Run only authorized synthetic documents through the tutorial's acceptance checks: retained originals/digests, custom extraction/confidence, explicit human gate, zero-failure native indexing, case/owner isolation, grounded existing-agent responses without tools, recovery, retention and cryptographic evidence. In the explicitly deferred mode, mark encryption attestations deferred/not certified rather than passed; report functional synthetic readiness separately, never regulated or production readiness. Observe asynchronous phases for a bounded deadline (30 minutes unless the user chooses another), honor Retry-After and retain operation/run identifiers for resume without persisting secrets.

Report completed and blocked stages, the chosen host/state owner and remaining approvals. Claim ready only after the acceptance checks pass. Do not fabricate certification, process real documents, promote to production or tear down resources without a separate request.
