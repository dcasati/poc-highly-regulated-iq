---
name: template-maintenance
description: Maintain and statically check the private document-review source, modular Bicep, Bash runner, devcontainer and Copilot guidance without live cloud operations or notebook execution.
---

# Maintain source

Read `AGENTS.md` and inspect the current diff before editing. Preserve unrelated user changes and staging. Ignored local configuration, state and outputs are user-owned; inspect filenames, not contents.

| Change | Contract to read |
| --- | --- |
| Infrastructure or inputs | `infra/bicep/main.bicep`, relevant module/types and sanitized examples |
| Deployment command interface | `run.sh`, `docs/getting-started.md` |
| Foundry/CU/Search handoffs | Relevant Bicep payload outputs and getting started |
| Authentication/application flow | `app/`, `docs/highly-regulated-scenario.md` |
| Developer tools | `.devcontainer/`, `docs/development.md` |
| Explicit Fabric item work | `fabric-workspace` skill; preserve workspace logical identities |

## Static checks only

```bash
bash -n run.sh
./run.sh -x check-deps
./run.sh -x build
```

Use the existing narrowly relevant offline checks for changed code; do not invent a deployment verification suite. Compile sanitized examples only, never expose real local parameters or copy credential profiles. If a source-only fixture is necessary, use a project-local directory and clean up only files you created.

Do not execute `what-if`, `install`, service REST, notebook cells or a live cloud call as maintenance. Static checks do not establish permissions, quota, preview availability, processing residency, DNS, indexing or application readiness.

Preserve Private Endpoints/public-access controls, controlled destination-scoped outbound NAT, scoped identity, no-tools direct Azure OpenAI inference, human publication and server-side case/owner authorization. Keep both full PDF layout indexing and corrected fields, the single-replica shared-process synthetic trust exception and an approved private administration access path. Keep the approved synthetic runtime mode with approval false and all encryption evidence exactly empty; retain optional evidence-gated inputs without attempting certification. Source removal never authorizes deletion of existing managed resources.

Update README, canonical getting started and sanitized examples when interfaces change. Keep Bicep modules small, API versions explicit and Bash readable. No Fabric initializer, staging environment, CI/CD pipeline or silent existing-resource adoption. Documentation-only changes need no cloud validation.
