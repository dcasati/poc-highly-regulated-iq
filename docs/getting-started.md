# Getting started

Deploy the synthetic document-review PoC with **modular Bicep + Azure CLI in Bash**. `infra/bicep/main.bicep` is the subscription entry point. `run.sh` calls native deployment commands; Content Understanding (CU), Search and Microsoft Graph still need the explicit handoffs below. Answers use direct private Azure OpenAI inference, not Managed Agent Service.

**Source changes are not deployment approval.** Use a new private PoC foundation, not another project's resources. Bicep does not silently adopt existing live resources; stop on name/ownership conflicts. Resuming a verified PoC requires its actual outputs and narrow modules, not rerunning initial network creation. No state migration or resource deletion is part of this guide.

## 1. Choose the target and prepare inputs

Confirm one approved private-network-connected execution host/checkout, selected subscription/directory, deployment caller, branding and explicit supported region. A normal Codespace is not automatically connected. Use approved authentication; do not grant yourself Graph permissions or change shared CLI defaults.

```bash
set -euo pipefail
set +x
umask 077
az account show --query '{subscription:id,tenant:tenantId}' --output json
SUBSCRIPTION=$(az account show --query id --output tsv)
./run.sh -x check-deps
command -v jq
mkdir -p .azure/checks
chmod 700 .azure/checks
```

Create ignored, owner-only `infra/bicep/examples/<stage>.local.bicepparam` files from the matching `.example.bicepparam` files **only if absent**. Examples are sanitized fixtures, not executable target configuration: replace all sample IDs, evidence and model/image values with approved inputs. Never save tokens, secrets or real documents in them. Check `git check-ignore` before saving deployment readbacks.

Review nonoverlapping address space, pinned administration image and approved package/tailnet/runtime/build destinations. NAT supplies outbound transport, not an allowlist. App/data ingress must use Private Endpoints only, public network access disabled, registry admin disabled and bypass `None`. An approved controlled outbound-only NAT public IP is permitted, not public ingress or unrestricted Internet approval.

Choose supported pinned model versions, quota and regional/Data Zone SKUs allowed by the parameter rules; **no Global SKUs**. The chat deployment must support system messages, `response_format: {type: "json_object"}` and `max_completion_tokens`. Assess direct inference, custom CU and native Search layout processing boundaries separately—resource location alone is insufficient. Global identity/control-plane services and Private DNS are not region-pinned.

## 2. Create the foundation and preserve CU defaults

```bash
export LOCATION="$APPROVED_REGION"
export DEPLOYMENT_NAME=review-foundation
export PARAMETERS_FILE=infra/bicep/examples/main.local.bicepparam
./run.sh -x build
./run.sh -x what-if
# STOP: approve the exact subscription, names and proposed changes before install.
./run.sh -x install
az deployment sub show --subscription "$SUBSCRIPTION" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs --output json > .azure/checks/foundation.outputs.json
```

The default template is `infra/bicep/main.bicep`; default scope is `subscription` and deployment name is `private-review`. Template/parameter paths resolve relative to the repository. `check-deps` requires `az`, `jq` and an existing Bicep executable on PATH or cached under `${AZURE_CONFIG_DIR:-$HOME/.azure}/bin/bicep`; it makes no cloud calls or compiler downloads/upgrades. `build` checks scope and parameter binding without generating JSON files.

`LOCATION` is required for cloud actions and sets subscription deployment metadata, **not resource regions**; select the approved resource `location` explicitly in local parameters. What-if reports resource IDs rather than properties, so review the source/parameters too. `install` performs one internal what-if, requires one visible `yes` approval and aborts if inputs change before creation. `show` prints only deployment name/state; use the explicit native `show --query properties.outputs` commands here for owner-only handoff files. To use a focused group module:

```bash
# Set ENTRY, LOCAL_PARAMETERS, TARGET_RG and STAGE for one row below.
export TEMPLATE_FILE="$ENTRY" PARAMETERS_FILE="$LOCAL_PARAMETERS"
export DEPLOYMENT_SCOPE=group RESOURCE_GROUP="$TARGET_RG" DEPLOYMENT_NAME="$STAGE"
./run.sh -x build
./run.sh -x what-if
# STOP: obtain separate approval before each install.
./run.sh -x install
az deployment group show --subscription "$SUBSCRIPTION" \
  --resource-group "$RESOURCE_GROUP" --name "$STAGE" \
  --query properties.outputs --output json > ".azure/checks/${STAGE}.outputs.json"
```

Use `resource_groups`, `network` and `services` from the foundation output to prepare later local parameters. Never guess physical names or principal IDs. `services.endpoints.openai` is the Azure OpenAI root endpoint; `services.models.chat` is its model deployment name.

There is no project, capability host, agent subnet, agent Blob/Cosmos store, connection or runtime binding stage. [Microsoft Learn](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/network) documents direct Azure OpenAI Private Endpoints with public access disabled. Verify normal private DNS and scoped managed-identity access before runtime; documentation does not establish this target's readiness. Tailnet enrollment/routes/ACLs and exact-PoC-hostname split DNS remain separate administrator approvals. The private administration VM remains the access path unless a specifically approved alternate private execution host and route/DNS path have been demonstrated; do not silently omit it.

### Explicit operator and application rights

The selected caller receives only account-scoped **Cognitive Services User** for the manual CU defaults/analyzer handoff and Search-scoped **Search Service Contributor** / **Search Index Data Contributor** for manual object registration and synthetic readiness reads. These are explicit operator prerequisites, not application permissions or automatic Graph consent. No caller Blob/Cosmos bootstrap grants are created. Review their continued need after setup; any grant cleanup requires separate approval.

The application identity receives container-scoped Blob access, Search Index Data Reader, Cognitive Services User for CU usage, Cognitive Services OpenAI User for inference and registry-scoped AcrPull. Search has access only to approved/evidence containers and the AI account for its native processing. The AI account's identity retains scoped OpenAI User for CU model execution; this is not a managed agent identity.

### CU defaults only

Read CU defaults and supported analyzer models first. Preserve unrelated mappings; only the specific new-account `ModelDeploymentsNotConfigured` error is an expected unconfigured state. Deploy `bootstrap-payloads.bicep` with reviewed supported mappings. Its outputs are requests, **not** applied configuration.

```bash
az rest --method get \
  --url "${CONTENT_ENDPOINT%/}/contentunderstanding/defaults?api-version=2025-11-01" \
  --resource https://cognitiveservices.azure.com/ \
  --output json > .azure/checks/defaults.before.json
az rest --method get \
  --url "${CONTENT_ENDPOINT%/}/contentunderstanding/analyzers/prebuilt-document?api-version=2025-11-01" \
  --resource https://cognitiveservices.azure.com/ \
  --output json > .azure/checks/supported-analyzer.json
```

For single emitted requests, use this Bash helper. `OUTPUTS` is a saved `properties.outputs` object; `KEY` is the selected output key, not an entire deployment response. Inspect the method/path/body privately and approve before calling it. Use a new body filename; do not overwrite existing readbacks.

```bash
send_request() {
  local request method path
  request=$(jq -ce --arg key "$KEY" '.[$key].value' "$OUTPUTS")
  method=$(jq -er '.method' <<< "$request")
  path=$(jq -er '.path' <<< "$request")
  test ! -e "$BODY_FILE"
  jq -ce '.body' <<< "$request" > "$BODY_FILE"
  az rest --method "$method" --url "${ENDPOINT%/}${path}" \
    --resource "$AUDIENCE" --body "@${BODY_FILE}" --output json
}

OUTPUTS=.azure/checks/bootstrap.outputs.json
KEY=content_defaults_request
BODY_FILE=.azure/checks/defaults.body.json
ENDPOINT="$CONTENT_ENDPOINT" AUDIENCE=https://cognitiveservices.azure.com/
send_request > .azure/checks/defaults.result.json
```

GET defaults again and compare declared mappings. This payload preserves unrelated CU defaults and emits no prompt-agent objects. Keep the chat deployment's blocking native RAI policy attached; application prompts and reference checks supplement it, not a claim of complete injection protection.

## 3. Platform, private links and knowledge

Deploy `scenario/platform.bicep` in the scenario group using this PoC's actual service/network outputs. Capture registry and runtime managed-identity IDs. Search reads only approved PDFs and corrected-field evidence, not originals/review state.

Deploy `scenario/private-links.bicep` in **Search's group**, after inspecting existing exact target/group pairs to avoid duplicate links. Target owners separately approve intended connections:

```bash
az network private-endpoint-connection approve --id "$VERIFIED_CONNECTION_ID" \
  --description "Approved private PoC dependency"
```

Require target-side `Approved` and Search-side `Succeeded` for Blob, `foundry_account` processing and `cognitiveservices_account` billing links. Stop on terminal failure or 30-minute timeout; never enable public access/bypass to recover.

Deploy output-only `knowledge/payloads.bicep` with the supported models, reviewed extraction fields, selected `geography`/`dataZone` processing location and verified private dependencies. Keep `application.field_names` aligned with the schema.

Use `send_request` with `OUTPUTS=.azure/checks/knowledge.outputs.json`, `KEY=analyzer_request`, a new `BODY_FILE`, CU endpoint and Cognitive Services audience. First GET the exact analyzer path: create if missing, skip if matching, and stop for separately approved replacement if an existing analyzer differs. After PUT, poll that analyzer's native status/readback until ready, within 30 minutes; stop on failure before Search writes.

The emitted Search requests are ordered: index → PDF/JSON data sources → layout skillset → PDF/JSON indexers → knowledge source → knowledge base. For each object, GET first; skip matching objects, stop on conflicting ownership/drift, approve any required PUT and compare the declared fields afterward. Preserve unrelated/server-added properties; use ETag `If-Match` where supported. A 404 means missing only when distinguished from auth/network failure.

The following is the native **write step for one already reviewed array entry** (`N=0` through `7`), not an unconditional bulk reconciler. For an existing object with an ETag, add `--headers "If-Match=$VERIFIED_ETAG"` to the PUT; stop and reread if that conditional update fails.

```bash
OUTPUTS=.azure/checks/knowledge.outputs.json
N=0 # Select the next approved missing/drifted owned object.
REQUEST=$(jq -ce --argjson n "$N" '.search_requests.value[$n]' "$OUTPUTS")
SEARCH_API_VERSION=$(jq -er '.search_api_version.value' "$OUTPUTS")
PATH_PART=$(jq -er '.path' <<< "$REQUEST")
BODY_FILE=".azure/checks/search-${N}.body.json"
test ! -e "$BODY_FILE"
jq -ce '.body' <<< "$REQUEST" > "$BODY_FILE"
az rest --method put \
  --url "${SEARCH_ENDPOINT%/}${PATH_PART}?api-version=${SEARCH_API_VERSION}" \
  --resource https://search.azure.com/ --body "@${BODY_FILE}" \
  --output json > ".azure/checks/search-${N}.result.json"
az rest --method get \
  --url "${SEARCH_ENDPOINT%/}${PATH_PART}?api-version=${SEARCH_API_VERSION}" \
  --resource https://search.azure.com/ --output json \
  > ".azure/checks/search-${N}.readback.json"
```

After a synthetic case is explicitly reviewed/published, run both indexers and read their statuses:

```bash
az rest --method post \
  --url "${SEARCH_ENDPOINT%/}/indexers/${INDEXER_NAME}/run?api-version=${SEARCH_API_VERSION}" \
  --resource https://search.azure.com/
az rest --method get \
  --url "${SEARCH_ENDPOINT%/}/indexers/${INDEXER_NAME}/status?api-version=${SEARCH_API_VERSION}" \
  --resource https://search.azure.com/ --output json
```

Require successful, nonempty synthetic approved-PDF and corrected-JSON indexing with no failed items, then authorized retrieval with case/owner filters and valid page references. Registration alone is not indexing readiness; unfiltered knowledge/MCP access is not authorization.

## 4. Private image, hosting and browser identity

Deploy `acr-build/main.bicep` for a new dedicated VNet-connected pool in the registry group, unless an approved private path already supplied the image. Wait for `Succeeded` and at least one instance, then:

```bash
az acr build --registry "$REGISTRY_NAME" --agent-pool "$AGENT_POOL_NAME" \
  --platform linux/amd64 --image review-portal:reviewed-build --file Dockerfile \
  --build-arg "RUNTIME_IMAGE=$APPROVED_RUNTIME_IMAGE_DIGEST" app/ReviewPortal
az acr repository show --name "$REGISTRY_NAME" \
  --image review-portal:reviewed-build --query digest --output tsv
```

`RUNTIME_IMAGE` must be a compatible .NET 10 runtime image pinned by immutable digest; no vendor-specific image layout is required. Use the built application's actual immutable digest for runtime, not the tag. No public build workers, registry keys, admin user or public-access exception.

Deploy `scenario/hosting.bicep` for Container Apps. Require an internal environment, disabled public networking, `managedEnvironments` Private Endpoint, peer encryption and private app-domain DNS pointing to the actual endpoint NIC. The returned default domain lets you prepare a private HTTPS SPA redirect; confirm the actual runtime URL afterward. Private endpoints/build resources incur costs; previews, quota and destination changes require review.

Use native Microsoft Graph only with separately approved directory authority. The identity Bicep modules emit bodies; ARM deployment does not create registrations:

1. `identity/api-payload.bicep`: single-tenant API, v2 delegated scope and user-only Caseworker/Reviewer roles.
2. `identity/spa-payload.bicep`: actual API `appId`, exact private redirect and authorization code/PKCE, no implicit flow or client secret.
3. `identity/finalize-payloads.bicep`: reviewed API PATCH/preauthorization and API/SPA service-principal requests.

Before Graph calls, compare the selected tenant with emitted `expected_tenant_id`. Search exact display names first; on resume GET actual object IDs and compare, do not repeat POST blindly.

```bash
test "$(az account show --query tenantId --output tsv)" = "$EXPECTED_TENANT_ID"
# Materialize api_request.body from identity-api.outputs.json as above.
az rest --method post --url https://graph.microsoft.com/v1.0/applications \
  --resource https://graph.microsoft.com/ --body @.azure/checks/api.body.json \
  --output json > .azure/checks/api.created.json
```

Save **object `id` and client `appId` separately**. Execute the emitted SPA request and each `graph_requests` entry individually, using its method/path/body with Graph endpoint/audience. API preauthorization and any organization-required consent are administrator decisions; no automatic Graph privilege grants.

An administrator separately assigns approved users through `POST /v1.0/servicePrincipals/<api-SP-object-id>/appRoleAssignments` with `{principalId: <user-object-id>, resourceId: <api-SP-object-id>, appRoleId: <emitted-role-id>}`. Reviewers require **both** application roles. These are not directory roles. Users get no direct Storage/Search/Foundry permissions.

## 5. Runtime and synthetic use

Prepare `scenario/runtime.bicep` parameters with real identities, verified private model inference, knowledge readiness, matching fields and the immutable image. Set `application.openai_endpoint` to the verified HTTPS Azure OpenAI root and `application.chat_deployment` to the actual JSON-capable deployment name. These become `Portal__OpenAIEndpoint` and `Portal__ChatDeployment`. The API sends `POST /openai/v1/chat/completions` with that deployment as `model` and requests `https://ai.azure.com/.default` for inference; CU remains on `https://cognitiveservices.azure.com/.default`. It sends no tools and creates no agent/thread/run. Verify the selected endpoint accepts this inference audience: current lifecycle guidance and the v1 REST reference differ on audience, and static checks cannot settle that live handoff. This user-approved PoC uses these exact `runtime` fields:

```bicep
attestation_mode: 'synthetic_poc_attestation_deferred'
approved: false
platform_evidence: ''
image_evidence: ''
transport_evidence: ''
```

The sanitized runtime example already selects this mode. Replace its remaining example identities, knowledge evidence and image hash with actual approved values; keep the three encryption evidence strings empty. Preserve the remaining runtime contract, including encryption controls, real identity and knowledge approval. The optional `evidence_gated` mode is not this PoC's chosen mode. **Synthetic documents only; no certification claim.** FIPS 140-3 encryption at rest/in transit is a requirement to assess for any future real deployment.

Review what-if and obtain separate runtime install approval. Read the actual `portal_url`; confirm private HTTPS, private managed-identity image/data access, a continuously running worker and denied public app/data access. Observe upload → extraction → every-field human confirmation → reviewer-only publication → both evidence paths indexed → case-authorized answers. Foreign cases/owners and invalid identity tokens must be rejected. See [application flows and authorization](highly-regulated-scenario.md).

Report infrastructure deployment and application readiness separately, with any blocked preview, quota, DNS, identity, processing-boundary or indexing handoff. Do not handle real documents, lock/delete evidence, broaden IAM or migrate existing ownership to overcome a blocker.

**Existing managed resources:** removing source definitions does not delete cloud capability hosts, projects, stores, subnets, connections or grants. Inventory only this PoC's owned resources during a separately approved cleanup, review dependencies/retention and approve each deletion independently. Never use complete-mode deployment or rerun the initial VNet to clear old children. Preserve ignored local state/configuration; this source reduction performs no migration or cleanup.
