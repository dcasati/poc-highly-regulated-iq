# Getting started

Deploy the synthetic document-review PoC with modular Bicep and Azure CLI in Bash. `infra/bicep/main.bicep` is the subscription entry point and `run.sh` wraps the native deployment commands. Content Understanding (CU), Search and Microsoft Graph need the explicit handoffs below; ARM deployment does not perform them.

**Source changes are not deployment approval.** Use a new private PoC foundation, never another project's resources. Stop on name or ownership conflicts: Bicep does not adopt existing resources. To resume, use the recorded outputs and the narrow module, not the initial network deployment. Guardrails live in [`AGENTS.md`](../AGENTS.md); application behaviour and trust limits in [the scenario](highly-regulated-scenario.md).

## 1. Choose the target and prepare inputs

Confirm one approved private-network-connected execution host, the subscription/directory, the deployment caller and an explicit supported region. A normal Codespace is not automatically connected. Do not grant yourself Graph permissions or change shared CLI defaults.

```bash
set -euo pipefail
set +x
umask 077
az account show --query '{subscription:id,tenant:tenantId}' --output json
SUBSCRIPTION=$(az account show --query id --output tsv)
./run.sh -x check-deps
mkdir -p .azure/checks
chmod 700 .azure/checks
```

Create ignored, owner-only `infra/bicep/examples/<stage>.local.bicepparam` files from the matching `.example.bicepparam` files, only if absent. Examples are sanitized fixtures: replace every sample ID, evidence, model and image value with approved inputs. Never store tokens, secrets or real documents in them, and confirm `git check-ignore` before saving readbacks.

Review these before the first what-if:

- Nonoverlapping address space, the pinned administration image and the approved package, tailnet, runtime and build destinations. NAT gives outbound transport, not an allowlist.
- Pinned model versions, quota and regional or Data Zone SKUs; **no Global SKUs**. The chat deployment must support system messages, `response_format: {type: "json_object"}` and `max_completion_tokens`.
- The processing boundaries of direct inference, the custom CU analyzer and native Search layout skills. Resource location alone does not settle them. Global identity services and Private DNS are not region-pinned.

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

Defaults: template `infra/bicep/main.bicep`, scope `subscription`, deployment name `private-review`. `LOCATION` sets deployment metadata, **not resource regions**; set each resource `location` in the local parameters. What-if lists resource IDs, not properties, so also review the source and parameters. `install` runs its own what-if, requires a visible `yes` and aborts if the inputs changed. `show` prints only the deployment name and state.

For a focused group module:

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

Use `resource_groups`, `network` and `services` from the foundation output for later parameters; never guess names or principal IDs. `services.endpoints.openai` is the Azure OpenAI root endpoint and `services.models.chat` the deployment name. Direct private access is described in [Microsoft Learn](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/network); verify private DNS and scoped managed-identity access on this target before runtime. Tailnet enrollment, routes, ACLs and exact-hostname split DNS are separate administrator approvals. Keep the private administration VM as the access path unless an approved alternative route has been demonstrated.

### Rights granted

The deployment caller gets account-scoped **Cognitive Services User** (manual CU handoff) and Search-scoped **Search Service Contributor** and **Search Index Data Contributor** (manual object registration and readbacks). These are operator rights, not application permissions or Graph consent. Review their continued need after setup; removing a grant needs separate approval.

The application identity gets container-scoped Blob access, Search Index Data Reader, Cognitive Services User (CU), Cognitive Services OpenAI User (inference) and registry-scoped AcrPull. Search reads only the approved-evidence containers and uses the AI account for native processing.

### CU defaults

Read the defaults and supported analyzer models first and preserve unrelated mappings. Only the new-account `ModelDeploymentsNotConfigured` error is an expected unconfigured state. Deploy `bootstrap-payloads.bicep` with reviewed supported mappings; its outputs are requests, **not** applied configuration.

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

To send one emitted request, use this helper. `OUTPUTS` is a saved `properties.outputs` object and `KEY` an output key. Inspect the method, path and body privately and approve before calling; use a new body filename.

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

GET the defaults again and compare the declared mappings. Keep the chat deployment's blocking RAI policy attached; it supplements, not replaces, the application's prompt and citation checks.

## 3. Platform, private links and knowledge

Deploy `scenario/platform.bicep` in the scenario group from this PoC's service and network outputs, and record the registry and runtime managed-identity IDs. Search reads only approved PDFs and corrected fields, never originals or review state.

Deploy `scenario/private-links.bicep` in **Search's group** after checking existing target/group pairs for duplicates. Target owners approve each intended connection:

```bash
az network private-endpoint-connection approve --id "$VERIFIED_CONNECTION_ID" \
  --description "Approved private PoC dependency"
```

Require target-side `Approved` and Search-side `Succeeded` for the Blob, `foundry_account` and `cognitiveservices_account` links. Stop on terminal failure or after 30 minutes; never enable public access or bypass to recover.

Deploy output-only `knowledge/payloads.bicep` with the supported models, reviewed extraction fields, `geography`/`dataZone` and verified private dependencies. Keep `application.field_names` aligned with the schema.

Use `send_request` with `OUTPUTS=.azure/checks/knowledge.outputs.json`, `KEY=analyzer_request`, a new `BODY_FILE`, the CU endpoint and the Cognitive Services audience. GET the analyzer first: create if missing, skip if matching, and stop for a separately approved replacement if it differs. After the PUT, poll its status for up to 30 minutes and stop on failure before any Search write.

Search requests are ordered: index → PDF/JSON data sources → layout skillset → PDF/JSON indexers → knowledge source → knowledge base. For each object, GET first; skip matches, stop on drift or unknown ownership, approve any PUT and compare afterward. Preserve server-added properties and use `If-Match` with the ETag where supported. Treat 404 as missing only when it is distinguishable from an auth or network failure.

This writes **one reviewed array entry** (`N=0` through `7`); it is not a bulk reconciler. For an existing object add `--headers "If-Match=$VERIFIED_ETAG"`, and reread if the conditional update fails.

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

After a synthetic case is reviewed and published, run both indexers and read their status:

```bash
az rest --method post \
  --url "${SEARCH_ENDPOINT%/}/indexers/${INDEXER_NAME}/run?api-version=${SEARCH_API_VERSION}" \
  --resource https://search.azure.com/
az rest --method get \
  --url "${SEARCH_ENDPOINT%/}/indexers/${INDEXER_NAME}/status?api-version=${SEARCH_API_VERSION}" \
  --resource https://search.azure.com/ --output json
```

Require nonempty, successful indexing of both approved PDFs and corrected JSON with no failed items, then case/owner-filtered retrieval with valid page references. Registration is not indexing readiness, and unfiltered knowledge access is not authorization.

## 4. Private image, hosting and browser identity

Unless an approved private path already supplied the image, deploy `acr-build/main.bicep` (a dedicated VNet-connected pool) in the registry group. Wait for `Succeeded` and at least one instance, then build:

```bash
az acr build --registry "$REGISTRY_NAME" --agent-pool "$AGENT_POOL_NAME" \
  --platform linux/amd64 --image review-portal:reviewed-build --file Dockerfile \
  --build-arg "RUNTIME_IMAGE=$APPROVED_RUNTIME_IMAGE_DIGEST" app/ReviewPortal
az acr repository show --name "$REGISTRY_NAME" \
  --image review-portal:reviewed-build --query digest --output tsv
```

`RUNTIME_IMAGE` must be a .NET 10 runtime image pinned by digest. Deploy the built image by its immutable digest, not the tag. Use no public build workers, registry keys or admin user.

Deploy `scenario/hosting.bicep`. Require an internal environment, disabled public networking, a `managedEnvironments` Private Endpoint, peer encryption and private app-domain DNS pointing to the endpoint NIC. Use the returned default domain to prepare the private HTTPS SPA redirect, and confirm the runtime URL afterward. Review cost, preview and quota before deploying.

Use native Microsoft Graph only with separately approved directory authority; ARM deployment creates no registrations. The identity modules emit request bodies:

1. `identity/api-payload.bicep`: single-tenant API, v2 delegated scope, user-only Caseworker and Reviewer roles.
2. `identity/spa-payload.bicep`: the API `appId`, exact private redirect, authorization code + PKCE, no implicit flow or client secret.
3. `identity/finalize-payloads.bicep`: API PATCH/preauthorization and API/SPA service-principal requests.

Compare the selected tenant with the emitted `expected_tenant_id` before any Graph call. Search exact display names first; on resume GET the actual object IDs and compare instead of repeating a POST.

```bash
test "$(az account show --query tenantId --output tsv)" = "$EXPECTED_TENANT_ID"
# Materialize api_request.body from identity-api.outputs.json as above.
az rest --method post --url https://graph.microsoft.com/v1.0/applications \
  --resource https://graph.microsoft.com/ --body @.azure/checks/api.body.json \
  --output json > .azure/checks/api.created.json
```

Save the object `id` and client `appId` separately, then execute the SPA request and each `graph_requests` entry individually. API preauthorization and any organization-required consent are administrator decisions.

An administrator assigns approved users with `POST /v1.0/servicePrincipals/<api-SP-object-id>/appRoleAssignments` and `{principalId, resourceId: <api-SP-object-id>, appRoleId}`. These are application roles, not directory roles, and users get no direct Storage, Search or Foundry rights. Reviewers need **both** roles.

## 5. Runtime and synthetic use

Prepare `scenario/runtime.bicep` with real identities, verified private inference, knowledge readiness, matching fields and the immutable image. Set `application.openai_endpoint` to the verified Azure OpenAI root and `application.chat_deployment` to the JSON-capable deployment; they become `Portal__OpenAIEndpoint` and `Portal__ChatDeployment`.

The API calls `POST /openai/v1/chat/completions` with the deployment as `model`, requests `https://ai.azure.com/.default` and sends no tools. CU stays on `https://cognitiveservices.azure.com/.default`. Current guidance and the v1 REST reference differ on the inference audience, so confirm the endpoint accepts it as a live handoff; never weaken authentication to recover.

The sanitized runtime example selects the user-approved synthetic attestation-deferred mode. Keep its three encryption evidence strings empty, `approved` false and the rest of the runtime contract; replace only the example identities, knowledge evidence and image hash. The full contract is in [Synthetic-only PoC](highly-regulated-scenario.md#synthetic-only-poc).

Review what-if and get separate approval, then read the actual `portal_url`. Confirm private HTTPS, managed-identity image and data access, a running worker and denied public access. Observe the full synthetic flow: upload → extraction → every-field confirmation → reviewer-only publication → both evidence paths indexed → case-authorized answers. Foreign cases/owners and invalid tokens must be rejected.

Report infrastructure deployment and application readiness separately, with any blocked preview, quota, DNS, identity, processing-boundary or indexing handoff. Do not use real documents, lock or delete evidence, broaden IAM or migrate ownership to get past a blocker.

**Cleanup:** source changes never delete cloud resources. Inventory only this PoC's resources under a separate approval, review dependencies and retention, and approve each deletion independently. Never use complete-mode deployment or rerun the initial VNet to clear old children.
