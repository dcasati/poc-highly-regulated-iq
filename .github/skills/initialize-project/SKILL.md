---
name: initialize-project
description: Configure local Bicep parameters for the private synthetic document-review PoC without deployment. Confirm branding, explicit region, private execution host and native service/identity handoffs.
---

# Configure local inputs

Read `AGENTS.md`, `docs/getting-started.md` and sanitized `infra/bicep/examples/`. If deployment was requested, let `deploy-platform` follow that guide; initialization does not mutate cloud resources.

Reuse confirmed host/checkout, subscription/directory, branding and supported region. Ask only for missing choices; never guess a region, physical ID, resource owner or credential. Do not discover/adopt unrelated resources. Inspect existing local filenames first and preserve user configuration.

Prepare owner-only ignored `<stage>.local.bicepparam` files beside their examples, only when they do not already exist. Fill nonsecret approved inputs; distinguish compiler fixtures from actual values. Keep destination-scoped egress, pinned model versions/SKUs/quota and processing boundaries explicit. Real service/identity IDs and the Azure OpenAI root endpoint/chat deployment come from later readbacks, not guessed names.

The runtime example selects this user-approved synthetic PoC mode: `attestation_mode: 'synthetic_poc_attestation_deferred'`, `approved: false`, and `platform_evidence`, `image_evidence`, `transport_evidence` exactly `''`. Preserve those fields; replace example identities, knowledge evidence and image hash with actual approved values. Do not fabricate readiness. Keep identity, knowledge, private networking and immutable-image requirements.

Verify files are ignored without printing their contents. Do not overwrite existing files, sign in, run what-if/install/REST, grant access, enroll a VM, or migrate state. Return configured stages and unresolved prerequisites.
