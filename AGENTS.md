# Repository guidance

This is a **private document-review proof of concept**, not the reusable upstream template. Use synthetic documents only. Other projects' resources are out of scope: do not read, reuse, adopt, peer with or modify them.

## Start here

- [Getting started](docs/getting-started.md) is the canonical deployment guide.
- `infra/bicep/` owns modular infrastructure; `run.sh` calls native Azure CLI in Bash.
- `app/` owns the private portal, API and extraction worker.

| Task | Repository skill |
| --- | --- |
| Deploy or resume the private platform | [deploy-platform](.github/skills/deploy-platform/SKILL.md) |
| Configure local inputs without deployment | [initialize-project](.github/skills/initialize-project/SKILL.md) |
| Change source or perform static checks | [template-maintenance](.github/skills/template-maintenance/SKILL.md) |

## Guardrails

- Use one approved private-network-connected execution host/checkout, selected subscription/directory and explicitly approved supported region. Keep model versions/SKUs/quota configurable. Reject Global model SKUs; assess direct Azure OpenAI inference, custom Content Understanding and native Search skill processing boundaries separately. Global identity/control-plane services and Private DNS are not region-pinned.
- Create a new PoC foundation. Bicep deployment does **not** silently take ownership of existing live resources; an `existing` declaration references a resource, not permission to modify it. Stop on conflicting names/ownership. No deployment, state migration, cloud deletion or ignored-file removal is authorized by a source-maintenance request.
- App/data ingress must use Private Endpoints only, with no public app/gateway IP and public network access disabled. Preserve private DNS, registry admin disabled and bypass `None`. Separately approved controlled outbound-only NAT is allowed; its public IP does not create public ingress. NAT is not an egress allowlist; maintain reviewed destinations and deny-other-egress controls.
- Tailscale is limited to approved synthetic-only administration. Enrollment, routes, ACLs and exact-PoC-hostname split DNS require separate approval. Never embed auth keys, auto-enroll, or override global service suffixes in a shared tailnet.
- The user approved `runtime.attestation_mode = 'synthetic_poc_attestation_deferred'` for this synthetic PoC only: `runtime.approved = false`; `platform_evidence`, `image_evidence` and `transport_evidence` must all be exactly `''`. Do not fabricate evidence or set approval true. Keep encryption controls, private networking, approved processing boundaries, real SPA/API authorization, immutable image, knowledge and human-review gates. FIPS 140-3 is a future real-deployment requirement, not a certification claim for this PoC. Preserve the optional evidence-gated contract without attempting certification as part of this workflow.
- Review native what-if and obtain approval before each infrastructure change. Use the narrow module when resuming; do not blindly PUT the initial VNet and reset child subnets. No complete-mode deployments. Report provisioned resources separately from application readiness.
- `run.sh -x install` performs ARM deployment only. Graph permissions/consent, user assignments, CU defaults/analyzer and Search objects are explicit native CLI/REST handoffs, never automatic privilege escalation. Use scoped managed identities; do not enable public endpoints or trusted-service bypass to overcome failures.
- Keep browser authorization real: single tenant, v2 delegated API scope, authorization code + PKCE, assigned application roles and server-enforced case/owner filters. No browser direct data-service access. Direct private Azure OpenAI chat inference sends no tools and uses only validated scoped Search evidence; no managed-agent resources or stores are required. Human confirmation is required before indexing both full PDFs and corrected fields.
- Portal/API/worker share one process and one replica as an explicit synthetic-only trust exception, not a parser/approval privilege boundary. Preserve owner plus Reviewer authorization and stale-version checks; real deployment needs a separately reviewed isolation decision.
- Keep the private administration VM unless an explicitly approved alternate private execution host and working route/DNS path replace it. Source reduction never deletes existing managed-agent resources; cleanup requires separate inventory, retention review and approval.
- Never print/commit credentials, tokens, real local parameters, `.env`, state, deployment outputs or debug logs. Verify local files are ignored and owner-only; preserve existing configuration and staging. Native REST tokens remain ephemeral.
- Do not introduce staging/promotion environments or CI/CD pipelines as part of this PoC.

## Conventions

Use typed/documented Bicep inputs, explicit API versions, focused modules and plain Bash + `az` commands. Keep root interfaces stable: `-x check-deps|build|what-if|install|show`; `TEMPLATE_FILE`, `PARAMETERS_FILE`, `LOCATION`, `DEPLOYMENT_SCOPE` (`subscription|group`), `RESOURCE_GROUP`, `DEPLOYMENT_NAME`.

Keep README, getting started and sanitized parameter examples aligned. Static maintenance may compile Bicep and check Bash syntax; it must not run what-if, install, service calls or notebooks. Store repeatable procedures in skills and product explanations in canonical docs, not session diaries. Do not persist physical deployment IDs or personal details.
