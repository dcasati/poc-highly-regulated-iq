# Deployment ownership

This PoC uses **Bicep + Azure CLI in Bash**, not CI/CD pipelines or staging/promotion environments. Follow [getting started](../docs/getting-started.md).

`run.sh` compiles or invokes native subscription/resource-group deployment commands. Foundry, Content Understanding, Search and Microsoft Graph handoffs remain explicit operator steps. Approve each exact live change and use one private-network-connected execution host.

`workspace/` is a disconnected inherited Fabric sample. Do not connect Fabric Git, seed notebooks or create deployment pipelines as part of the review application setup. If Fabric item work is explicitly requested, use the [fabric-workspace skill](../.github/skills/fabric-workspace/SKILL.md) and preserve its portable logical identities.

Existing live resources retain their owners. Source changes do not authorize resource adoption, deletion or state migration.
