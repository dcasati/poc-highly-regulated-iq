# Bicep deployment

Use [getting started](getting-started.md) for the canonical Bicep + Azure CLI procedure, including the explicit Foundry, Content Understanding, Search and Microsoft Graph handoffs.

`infra/bicep/main.bicep` is the subscription entry point. Focused modules handle operations that need service readbacks or separate approval. `run.sh` supports `check-deps`, `build`, `what-if`, `install` and `show`; installation does not bootstrap data planes or grant Graph permissions.

Do not deploy over existing live resources merely because Bicep source exists. Confirm ownership and approve the exact target first; no migration is implied.
