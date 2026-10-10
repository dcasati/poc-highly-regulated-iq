# Repository guidance

This is a **derived private document-review proof-of-concept repository**, not the reusable upstream template. It owns its new private foundation, deployment configuration, scenario infrastructure and secured Terraform state. Unrelated projects' resources are out of scope: do not read, reuse, import, peer with or modify them. Deployment is not complete until the documented live readiness checks pass.

## Start here

- [Getting started](docs/getting-started.md) is the canonical deployment guide; [developer setup](docs/development.md) covers Codespaces and Copilot App/CLI.
- `infra/` owns infrastructure, permissions and knowledge registration. Use plain Terraform and one ignored local tfvars file.
- `workspace/` owns Fabric definitions and bootstrap notebooks, not infrastructure, credentials or data backups.
- [`cicd/`](cicd/README.md) owns native Git/bootstrap/promotion guidance. [Ontology knowledge](docs/ontology-knowledge.md) explains binding and delegated retrieval.

Load the matching repository skill before its workflow:

| Task | Skill |
| --- | --- |
| "Deploy the platform" or resume private document-review setup | [deploy-platform](.github/skills/deploy-platform/SKILL.md) |
| Configure the private scenario without deployment | [initialize-project](.github/skills/initialize-project/SKILL.md) |
| Change or statically validate the template/toolchain | [template-maintenance](.github/skills/template-maintenance/SKILL.md) |
| Edit Fabric items, inspect bindings, bootstrap or promote | [fabric-workspace](.github/skills/fabric-workspace/SKILL.md) |

## Always-on guardrails

- Provision a new private PoC foundation in an explicitly approved supported Azure region. Do not discover unrelated resources to use as prerequisites. Use a region and model SKU permitted by the deployment's validation rules; reject Global model deployment SKUs and validate the selected processing boundary separately for agent inference, custom Content Understanding and native skills. Global Azure control-plane services, Entra ID and Private DNS are not region-pinned resources.
- `infra/connectivity/` owns only the new PoC network and private administration VM. Tailscale is explicitly limited to synthetic-only PoC administration, not FIPS-validated application transport. `infra/state-backend/` bootstraps the private/keyless state store, reserved endpoint subnet and PoC Blob DNS zone. The separately approved exceptions permit owner-only local bootstrap state for these two roots on the encrypted authoritative Mac; foundation/scenario/build-pool roots still require secured remote state. Backend apply and its container-scoped role grant, each existing-state migration, VM apply/enrollment and tailnet route/ACL/DNS changes require explicit approvals. Use exact PoC hostnames for split DNS in a shared tailnet, not global service-suffix overrides. Never put tailnet auth keys in Terraform or auto-enroll the VM.

- Never run live `plan`, `apply`, `destroy`, notebook execution or deployment tests as a template-maintenance check. Live work requires a derived repository and an explicitly chosen target.
- The private review scenario uses `app/` and the separate `infra/highly-regulated/` root, following `docs/highly-regulated-scenario.md`. Its optional `infra/acr-build/` root owns only a new private-registry build pool, with separate state; keep existing registry/network ownership and public-access settings unchanged. Do not run the Fabric initializer/bootstrap or apply the legacy `infra/` root for this deployment. The hard FIPS requirement is FIPS 140-3 encryption at rest/in transit, not whole-app/hash/JWT certification. Runtime defaults to accepted encryption-path evidence; algorithms, FIPS nodes and private build pools alone do not validate those paths. Only explicit user authorization permits `runtime_attestation_mode = "synthetic_poc_attestation_deferred"` (Bicep `runtime.attestation_mode`), with approval false and all encryption evidence exactly empty. This exception is synthetic-only, deferred/not certified, never production-ready; private networking, no public app/data ingress, encryption controls, approved processing boundaries, immutable image, real SPA/API authorization, knowledge and human-review gates remain mandatory.
- Private ingress means no public inbound app/data endpoint and no `publicIPAddress` assigned to the app or its ingress gateway. Explicitly approved controlled outbound-only NAT is acceptable and does not expose unsolicited inbound access; its public IP is not a private-ingress deployment blocker. This is not approval for unrestricted Internet egress, IAM/permission broadening or public access. Preserve Private Endpoints/DNS, disabled public network access, registry admin disabled and bypass `None`. A literal zero-public-IP inventory is a separate optional stricter architecture requiring its own approved egress design, not an implied AKS migration.
- Route "deploy the platform" to the complete private scenario workflow: existing-resource preflight, approved platform/knowledge plans, private ACR build and approved runtime plan, then synthetic readiness checks. Use one confirmed execution host/checkout/backend throughout; do not create duplicate state in an App worktree. Require plan approvals and distinguish deployed resources from verified readiness.
- Do not delete cloud assets, local state or ignored configuration without explicit permission. Preserve unrelated user changes and staging.
- Never commit or print credentials, real tfvars, `.env`, state, saved plans or debug logs. Keep PATs ephemeral/write-only; rotate with `github_token_version`. Provider-returned secrets can remain in state: require secured remote state before team/CI use.
- Use `project_name` for resource branding; require an explicit region. Discover subscription/authentication through provider-supported CLI/environment conventions. Never bake a repository owner, tenant, subscription or physical Fabric ID into shared definitions.
- Preserve `.platform` logical IDs, TMDL lineage tags and binding markers: these are portable model identities, **not** deployment IDs. Resolve physical bindings in the current Fabric workspace. Keep the template ontology unbound; review generated DEV bindings only in derived repositories.
- Keep setup staged: Terraform platform -> native Git sync with an explicitly attached plan -> Terraform knowledge using physical DEV item GUIDs. No Terraform Git/seeding provisioners or custom deployment wrapper. TEST starts empty; tenant settings and PROD/approval gates are not template-owned.
- Preserve insert-only seeding, schema checks, current-workspace scope and explicit opt-in outside DEV/TEST. Preserve binding identity checks, unrelated definition parts, bounded polling and failure propagation. Serialize authoring/deployment; rebind every promoted target.
- Keep Search knowledge objects in data-plane `restful_resource` resources, with CRUD/drift detection and source rebuild/deletion ordering. Leave the source/base/MCP connection disabled when `knowledge_lakehouse_id` is null.
- Use native `fabricOntology` sources for live ontology queries. They require an end-user Search-audience token in `x-ms-query-source-authorization`; managed identities do not replace it. OneLake indexing's Search identity needs Contributor on DEV only, not a read-only lakehouse grant or access to TEST/PROD.
- Surface failures and documented preview/cost/public-networking limitations. A successful seed, deployment or registration is not proof of indexing, binding, graph or query readiness.

## Conventions and learning

Use snake_case Terraform labels, typed/documented inputs and outputs, explicit API versions and configurable model versions/SKUs/quota. Prefer native resources, keep `.terraform.lock.hcl`, and limit drift exclusions to documented service behavior.

Keep reusable learning at the narrowest useful scope: cross-task safety rules here, repeatable procedures in the matching skill, and product explanations in canonical docs. Correct the existing source instead of appending a session diary or duplicating instructions. Do not persist deployment IDs, credentials, personal details or unverified assumptions as guidance.

Keep README, getting started and the sanitized tfvars example aligned. Static Terraform checks are `init -backend=false`, `fmt -check -recursive`, and `validate`; use an isolated configuration copy when local deployment files exist. The maintenance skill explains safe checks for tooling and notebooks. Do not bundle project-specific deployment tests.
