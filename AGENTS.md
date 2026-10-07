# Repository guidance

This is a **derived private document-review proof-of-concept repository**, not the reusable upstream template. It owns its new US-only foundation, deployment configuration, scenario infrastructure and secured Terraform state. Unrelated projects' resources are out of scope: do not read, reuse, import, peer with or modify them. Deployment is not complete until the documented live readiness checks pass.

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

- Provision a new US-only PoC foundation. Do not discover unrelated resources to use as prerequisites. All regional resources and AI processing must remain in the US; reject Global model deployment SKUs and validate custom Content Understanding and native-skill processing boundaries separately. Global Azure control-plane services, Entra ID and Private DNS are not region-pinned resources.
- `infra/connectivity/` owns only the new US PoC network and private administration VM. Tailscale is explicitly limited to synthetic-only PoC administration, not FIPS-validated application transport. The user-approved exception permits owner-only local bootstrap state for this root only on the encrypted authoritative Mac; platform/build-pool roots still require secured remote state. Backend creation/migration, VM apply, enrollment, tailnet routes/ACLs and split DNS require their own approvals. Never put tailnet auth keys in Terraform or auto-enroll the VM.

- Never run live `plan`, `apply`, `destroy`, notebook execution or deployment tests as a template-maintenance check. Live work requires a derived repository and an explicitly chosen target.
- The private review scenario uses `app/` and the separate `infra/highly-regulated/` root, following `docs/highly-regulated-scenario.md`. Its optional `infra/acr-build/` root owns only a new private-registry build pool, with separate state; keep existing registry/network ownership and public-access settings unchanged. Do not run the Fabric initializer/bootstrap or apply the legacy `infra/` root for this deployment. Runtime deployment requires approved cryptographic evidence; FIPS nodes and private build pools do not validate container images.
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
