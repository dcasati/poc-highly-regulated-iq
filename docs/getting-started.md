# Getting started

This derived repository deploys the **private document-review scenario**, not the upstream Fabric development baseline. The [scenario tutorial](highly-regulated-scenario.md) is the detailed deployment and acceptance guide.

## Establish ownership before provisioning

Use the published, reviewed repository commit on one approved execution host with private connectivity. Reuse any existing configuration/backend for this deployment; missing files in an App worktree are not permission to create a second state owner.

Configure distinct secured remote backend keys for `infra/foundation/`, `infra/highly-regulated/` and, if required, `infra/acr-build/` and `infra/browser-identity/`. Keep credentials, real tfvars, backend configuration, saved plans and state out of Git. The subscription comes from the selected Azure CLI account or standard `ARM_*` variables, not committed configuration.

This deployment must use **new PoC-owned US resources**. Unrelated projects are excluded: do not reuse their registry, networking or AI services, import them or create peering. Start with the reviewed [`infra/connectivity/`](../infra/connectivity/README.md) root when private access is missing, then the separately reviewed [`infra/state-backend/`](../infra/state-backend/README.md) root for private/keyless US state storage. These bootstrap roots own the network/router and state/DNS/endpoint subnet, not the AI foundation. Each has its own narrowly approved encrypted-host, owner-only local-state exception. Backend apply, its scoped identity grant, exact-hostname split DNS and each state migration require approval; later roots require secured remote state.

## Confirm prerequisites

Provision the new US AI foundation through [`infra/foundation/`](../infra/foundation/README.md) before using the scenario root. Start with the private account/dependencies/models stage, verify exact-hostname DNS and keyless private access, then review project creation, verified project provisioning roles/AAD connections, the native capability host and discovered runtime bindings in separate plans. The host uses the documented capability-host preview, not account `capabilitySettings`; it retains private/keyless controls. Configure supported Content Understanding defaults and bootstrap/verify the prompt agent over private endpoints. The connectivity root does not create these services. Scenario data sources must reference only that verified PoC-owned foundation. Administrators own SPA/API registrations, consent, user roles, certificates and immutable retention; no tenant-wide permissions are granted automatically.

Use supported US regional or US Data Zone model deployments rather than Global SKUs. Validate Content Understanding resource-region support and both custom-analyzer and native-skill processing boundaries. Global control-plane services, Entra ID and Private DNS aren't region-pinned; resource placement alone does not establish US-only processing or FIPS compliance.

Supply a generic project name and explicit region, verified existing-resource references and approved subnet choices. The hard FIPS requirement is encryption at rest and in transit using FIPS 140-3 validated modules, not independent whole-app/hash/JWT certification. Supply accepted image TLS, platform/service and transport encryption evidence. AES-256, TLS or private connectivity alone does not prove module validation.

## Follow the staged workflow

Attestations default to fail-closed `runtime_attestation_mode = "evidence_gated"`.
Only explicit user authorization permits `"synthetic_poc_attestation_deferred"`
for a synthetic-only PoC: retain `compliance.approved = false` and exactly empty
platform/image/transport evidence. Bicep's equivalent is
`runtime.attestation_mode`. See [the canonical exception](highly-regulated-scenario.md#explicit-synthetic-poc-attestation-deferral):
private endpoints/no public app/data ingress, encryption controls, US processing, identity,
knowledge, image digest and human review are not waived. Report deferred/not
certified, never production ready; each exact runtime plan still needs approval.

Require no public inbound app/data endpoint or `publicIPAddress` assigned to the
app or its ingress gateway. Explicitly approved controlled outbound-only NAT is
acceptable and does not expose unsolicited inbound access; accepted NAT is not
a deployment blocker. This does not authorize unrestricted Internet egress,
IAM/permission changes or public access. Preserve Private Endpoints/DNS, disabled
public network access, registry admin disabled and bypass `None`. A literal
zero-public-IP inventory is an optional stricter architecture, not a requirement
to migrate hosting. Exact native/saved-plan approvals remain unchanged.

Choose one infrastructure owner per resource boundary:

| Path | Use |
| --- | --- |
| Terraform (current live owner) | Follow the approved saved-plan procedure below without changing state ownership. |
| [Parallel Bicep](../infra/bicep/README.md) | Separate staged ARM sources for newly authorized boundaries; Search/CU CRUD and Kubernetes remain explicit operator steps. Initial platform preparation creates no hosting/runtime/knowledge or portal URL. |

Bicep lives alongside Terraform, not over it. Its source availability does not
authorize deployment over today's live assets; ownership migration requires
separate review. Private networking, state safeguards, identity, immutable image
and exact image/platform/transport evidence (or the explicit synthetic-only
deferral above) and synthetic acceptance still apply.
The existing **"Deploy the platform"** workflow remains Terraform-based.

1. Configure the ignored scenario tfvars on the chosen host and review/apply the saved **platform** plan with `provision_hosting`, `deploy_knowledge` and `deploy_runtime` false. Browser identity can remain null for this registry/data/managed-identity stage.
2. Approve the required processing/billing shared links through their owners; review/apply the saved **knowledge** plan.
3. Use an approved private ACR build pool, or review/apply the separate **build-pool** plan. Build with `az acr build --agent-pool` and the approved runtime image digest.
4. Review dependency egress and the separate **hosting** plan, enabling `provision_hosting`. Verify the output image digest in the scenario's runtime registry, complete browser identity/compliance approvals and review/apply the saved **runtime** plan. An authorized administrator can use the optional `infra/browser-identity/` root for new single-tenant SPA/API registrations and separately approved operator application roles; add exact HTTPS redirects only after discovering the real private hostname.
5. Run synthetic-only identity, network, extraction, human-review, indexing, case-isolation, recovery and cryptographic acceptance checks.

In Copilot App or CLI, say **"Deploy the platform."** The [repository skill](../.github/skills/deploy-platform/SKILL.md) coordinates these stages without AZD hooks, custom deployment wrappers, automatic plan approval or a claim that an apply proves readiness.

Do not run the inherited Fabric initializer, apply `infra/`, synchronize its workspace items or execute its notebooks for this scenario. Those files are upstream reference material only.

See [developer setup](development.md) for execution-host routing and local synthetic checks.
