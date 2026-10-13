---
name: deploy-platform
description: Deploy or resume the synthetic private document-review PoC with modular Bicep and Azure CLI in Bash. Use for "deploy the platform" or "deploy this project". Require approved private targets and explicit native service/identity handoffs.
---

# Deploy the private platform

Read `AGENTS.md` and follow **`docs/getting-started.md`**, the single canonical command guide. Read `docs/highly-regulated-scenario.md` for application/auth constraints. Do not create another runbook.

1. Reuse the confirmed source, one approved private execution host/checkout, subscription/directory and supported region. A Codespace is not automatically VNet-connected. Inspect local configuration filenames without exposing contents. Missing local files do not authorize a new deployment over existing resources.
2. Confirm this is a new PoC foundation or a resume of its verified owned resources. Do not discover/reuse unrelated infrastructure. Keep model version/SKU/quota explicit; reject Global SKUs and assess inference, custom CU and native skill processing boundaries separately.
3. Prepare owner-only ignored `*.local.bicepparam` files from `infra/bicep/examples/`. Compile using `run.sh -x build`; review native what-if and require approval for the exact installation. The default entry is `infra/bicep/main.bicep`, subscription scope. Use focused group modules when resuming; do not blindly reset the VNet.
4. Follow the guide's private service/model readbacks, preserved native CU defaults/analyzer requests, platform/private-link/knowledge handoffs and private ACR build. Bicep outputs are request bodies, not proof that data-plane objects exist. GET and compare before writes; preserve successful objects and unrelated fields.
5. Use separately authorized Graph operations for the single-tenant API/SPA, custom scope, PKCE and user application roles. Never grant directory roles/Graph consent automatically. No browser direct data-service access.
6. Deploy private Container Apps hosting and immutable runtime only after real identity, knowledge, direct-model and image prerequisites exist. Then:
   - Use `application.openai_endpoint` and `chat_deployment`; verify JSON-capable private inference with the application's `https://ai.azure.com/.default` scope and no tools (CU remains Cognitive Services; Search uses `https://search.azure.com/`). Treat the documented audience discrepancy as a live readiness handoff, never weaken auth to recover.
   - Retain both full PDF and corrected-field indexing and the explicit shared-process synthetic trust exception.
   - Keep the user-approved synthetic-only `runtime.attestation_mode = 'synthetic_poc_attestation_deferred'`: `approved = false`; all three encryption evidence strings exactly empty.
   - Preserve all private/auth/processing/human-review gates. No certification work or claims are part of this PoC.
7. After an authorized synthetic case is human-reviewed and published, `scripts/check_synthetic_readiness.py` is a read-only indexing gate (`--help` lists its inputs). Search is private with local auth disabled, so run it on the administration VM after `az login` there; elsewhere it exits 2. It never proves acceptance. Observe the complete synthetic browser flow and case/owner isolation before reporting readiness. Distinguish infrastructure deployment, native object registration and application readiness; report blockers without public-access or permission workarounds.

Use Bash + native `az`/`az rest`, with ephemeral authentication and owner-only ignored readbacks. `run.sh` does not grant Graph permissions or bootstrap data planes. No staging environment, CI/CD pipeline, state migration, cloud deletion or implicit resource adoption.

Tailnet enrollment/ACL/routes/exact-hostname DNS and target-owner private-link approvals remain separately authorized administrator actions. Controlled outbound NAT is permitted only for reviewed dependencies; it is not public ingress or unrestricted egress approval.

Record each standing exception (Tailscale egress, temporary operator grants) with an owner and review date per `docs/getting-started.md` "Standing exceptions", and remove it when due.

Keep the administration VM unless a specifically approved alternate private execution host and route/DNS path work. Cleanup needs separate ownership/retention review and approval.
