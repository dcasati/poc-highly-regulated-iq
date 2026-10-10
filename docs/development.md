# Development and Copilot

[Getting started](getting-started.md) is the canonical deployment guide. Use Bicep and native Azure CLI commands in Bash; no staging or CI/CD setup is required.

## One execution host

Use one approved checkout for configuration, authentication and deployment. Azure CLI, an existing local Bicep executable, Bash and `jq` are needed for the deployment guide. The runner accepts Bicep on PATH or already cached under `${AZURE_CONFIG_DIR:-$HOME/.azure}/bin/bicep`; it does not download or upgrade Bicep. Application development also needs the .NET 10 SDK, Git and Python for local browser checks and diagram authoring. Copilot, GitHub CLI, ripgrep and SSH tooling are optional for their respective workflows, not deployment dependencies. No Node/npm toolchain or local Docker daemon is required to build the portal through private ACR.

A normal Codespace is **not automatically connected to the Azure VNet**. Choose an approved private-network-connected host, or verify the selected Codespace's connectivity first. In Copilot App, route commands and file edits to that same checkout. Use authenticated `gh codespace ssh`; do not publish SSH ports or bypass host verification.

Use the organization's existing approved Azure identity and explicit subscription/directory. If an isolated CLI profile is selected, use its confirmed `AZURE_CONFIG_DIR` in every shell; do not copy tokens or change shared CLI defaults. Do not sign in, grant permissions or change another project's network automatically.

Private service names must resolve normally to their Private Endpoint addresses on that host. For shared-tailnet split DNS, use only separately approved exact PoC hostnames and preserve unrelated resolvers. Enrollment, routes and ACL changes are administrator actions, not initialization.

## Configuration and commands

Tell Copilot **"Initialize the project"** to prepare owner-only ignored `*.local.bicepparam` files from `infra/bicep/examples/`, without cloud operations. Tell it **"Deploy the platform"** to follow the canonical guide with separate approval gates.

```bash
bash -n run.sh
./run.sh -x check-deps
./run.sh -x build
# Check application/diagram authoring dependencies separately:
bash .devcontainer/check-tools.sh -x check-app
```

The devcontainer runs `check-app` after creation and includes Pillow and Liberation Sans for [diagram generation](diagrams/README.md). Browser checks require Playwright and its browser installed separately; they are not part of the deployment dependency check.

These source checks do not establish cloud permissions, service availability, quota, DNS, indexing or application readiness. `what-if`, `install` and service REST calls are live operations, not static checks.

Keep real parameters, original documents, credentials, deployment outputs and logs out of Git. Preserve existing live resources, local configuration and unrelated user changes. Source simplification does not authorize deployment or state migration.
