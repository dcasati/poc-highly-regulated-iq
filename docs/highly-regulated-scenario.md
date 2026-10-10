# Private document review

For deployment commands, use [getting started](getting-started.md). This guide describes the application rather than duplicating infrastructure instructions.

## Architecture and ownership

The [README](../README.md) shows the application and network diagrams.

The application supports human review of manually exported PDF packages, such as Form 3500 exemption applications. Its extraction schema is configurable; it is not a bundled eligibility model. There are no business-system connectors or automated eligibility decisions.

`infra/bicep/` creates the private PoC foundation and application infrastructure. Inference calls Azure OpenAI directly. Source changes never delete deployed resources; cleanup requires separate approval.

## Application flows

1. **Intake:** an authenticated Caseworker uploads a PDF. The API derives owner identity from the authenticated tenant object ID, not a browser-supplied owner. Originals and durable review state are retained separately.
2. **Extraction:** the continuously running worker invokes the custom Content Understanding analyzer privately. Fields, confidence, missing values and source evidence remain proposals.
3. **Human review:** a Reviewer corrects and explicitly confirms every field. Missing/unknown/low confidence is visible; stale or partial review cannot publish. Reviewers require both Caseworker and Reviewer roles.
4. **Publication:** only after approval are a PDF copy and corrected field JSON published to the two Search-readable containers. Original/review-state containers are not Search sources.
5. **Questions:** the API enforces both case and owner filters on Foundry IQ knowledgebase/source retrieval, validates structured `sourceData` records and their content, and sends only that scoped evidence to direct private Azure OpenAI chat completions. It supplies the deployment name as `model`, requests `https://ai.azure.com/.default` for inference and sends no tools (CU keeps the Cognitive Services scope). Answers use bounded JSON `{answer, citations:[ids]}`; unknown citation IDs or tool/function output are rejected. Valid source identity is not proof that a statement is entailed by that source. Another user's evidence must never be retrieved or cited.

The approved PDF path retains native document layout/chunk/page indexing, alongside corrected-field JSON. Extraction of selected fields does not demonstrate full-page text coverage, so it cannot replace full-document indexing.

The worker records a durable extraction lifecycle and failure code; unknown submission outcomes do not automatically resubmit and risk duplicate billable work. The owner must explicitly acknowledge that risk when retrying `SubmissionOutcomeUnknown`. Retry uses the current case version; stale requests fail closed. The case list returns `{items, continuationToken}` with fixed 50-item pages and a `continuationToken` query; failure on one listed case must not hide the remaining page. Reviewer-only `/api/worker/status` supports operational visibility, not extraction or indexing acceptance.

## Authentication

Use a single-tenant Entra SPA and API. The browser uses authorization code with PKCE, not a client secret or implicit flow. The API requires v2 delegated `access_as_user` tokens and assigned application roles; reject wrong-tenant/audience, unsigned or expired tokens.

API preauthorization of the selected SPA, any organization-required consent and user role assignments are separate administrator decisions. No directory roles or tenant-wide Graph permissions are automatically granted. Users receive no direct Storage, Search or Foundry access.

Prompt instructions ask the model to reject unrelated tasks and treat retrieved text as untrusted; they are advisory, not an enforced boundary. The JSON-capable deployment must support system messages, JSON object output and `max_completion_tokens`; its native blocking RAI policy remains enabled. These controls do not remove the need for server-side authorization or human judgment.

**Synthetic trust exception:** portal, API and extraction worker share one process, managed identity and a single replica. Owner plus Reviewer checks, every-field confirmation and stale-version checks gate publication, but a compromised process can cross both parsing and approval authority. This deliberately relaxes privilege separation for synthetic inputs only; it is not an enforced process boundary or a production isolation claim. Real documents require a separately reviewed isolation design.

Publication verifies hashes and uses `If-None-Match` to avoid silently overwriting an existing revision. Approved-PDF metadata includes `original_sha256`, deterministic reviewed-revision fingerprint `review_sha256`, `reviewed_at`, `reviewer_id`, and owner/case/source identifiers. These application checks are **not IAM-level immutability**: the runtime's Blob Contributor rights can modify originals, approved evidence and state. Mismatched revisions are detected and rejected against the recorded hashes, not silently overwritten; a compromised identity that rewrites both content and trusted state remains outside this protection. Retention locks and IAM/process privilege separation require separately approved work.

## Private networking

App/data ingress uses Private Endpoints only. Container Apps has an internal environment, public network access disabled and a `managedEnvironments` Private Endpoint. The application's domain resolves to that endpoint's NIC address, not the environment ILB. Supporting stores and registry retain private access, keyless identity, registry admin disabled and bypass `None`.

An explicitly approved controlled outbound-only NAT public IP is acceptable: it supports required outbound dependencies and does not expose unsolicited inbound access. NAT alone does not restrict destinations. Preserve destination-scoped controls; do not broaden them to unrestricted Internet egress. Entra sign-in is identity HTTPS, not a customer Private Endpoint.

## Synthetic-only PoC

The user explicitly approved deferred attestation for synthetic documents:

```bicep
attestation_mode: 'synthetic_poc_attestation_deferred'
approved: false
platform_evidence: ''
image_evidence: ''
transport_evidence: ''
```

These are fields inside `runtime`; other runtime fields still need real supported service references, SPA/API identities, knowledge readiness and an immutable image digest. Deferral does not waive private networking, encryption controls, approved processing boundaries, authorization, retained originals or human confirmation.

Use synthetic documents only. FIPS 140-3 encryption at rest/in transit is a requirement to assess before any future real deployment; this PoC makes no certification claim. The optional `evidence_gated` contract remains available for separately reviewed evidence, but is not this PoC's selected mode.

## Before calling the application ready

Observe the complete synthetic browser workflow: upload, extraction, correction, every-field confirmation, reviewer-only publication, both evidence paths indexed, authorized answers with page/source references, and rejection of foreign cases/owners. Confirm a continuously running worker, private image pulls, normal private DNS and denied public app/data access. Record failures and preview/cost/quota limitations; successful infrastructure deployment or isolated service calls are not complete application readiness.

Retention locking, deletion and recovery actions require separate approval. Do not process real documents or silently change existing ownership to finish the PoC.
