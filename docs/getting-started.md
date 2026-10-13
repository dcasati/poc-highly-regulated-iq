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

Use `resource_groups`, `network` and `services` from the foundation output for later parameters; never guess names or principal IDs. `services.endpoints.openai` is the Azure OpenAI root endpoint and `services.models.chat` the deployment name. Direct private access is described in [Microsoft Learn](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/network); verify private DNS and scoped managed-identity access on this target before runtime. Tailnet enrollment, routes, ACLs and exact-hostname split DNS are separate administrator approvals. Keep the private administration VM as the access path unless an approved alternative route has been demonstrated. Data-plane `az rest` calls in §2–§3 must run on that VM (see [Not created by Bicep](#not-created-by-bicep)); a workstation resolving public addresses is refused.

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

### Build pool egress and offline restore

The `snet-<project>-build` NSG denies other egress, so the dedicated pool stays in `Creating` until the reviewed dependencies are allowed. Set `platform_destinations.build` (or `outbound.build`) to Azure service tags, never Internet or `AzureCloud`: region-scoped `AzureKeyVault.<Region>`, `Storage.<Region>` and `EventHub.<Region>` (for example `Storage.WestUS3`), global `AzureMonitor` (443 and 12000), plus `MicrosoftContainerRegistry.<Region>` and `AzureFrontDoor.FirstParty` (443) for base images. Bare `Storage`, `EventHub` and `AzureKeyVault` tags cover every region and tenant, so the validator rejects them. Entra, the registry Private Endpoint and DNS are already allowed. These service tags are accepted in `destination_cidr` for build rules only; see `examples/main.example.bicepparam`. On an already-deployed foundation add them with narrow `az network nsg rule create` calls instead of re-running the VNet.

NuGet is not a service tag, so the pool cannot restore from nuget.org. Restore on a trusted workstation into a feed folder inside a staging copy of `app/ReviewPortal` (without `bin/`/`obj/`), then build with `NUGET_SOURCE` pointing at it; `--locked-mode` still verifies the lock file:

```bash
dotnet restore --locked-mode --packages ./nuget-offline
az acr build ... --build-arg NUGET_SOURCE=/src/nuget-offline .
az acr task show-run --registry "$REGISTRY_NAME" --run-id "$RUN_ID" --query 'outputImages[].digest' --output tsv
```

With public network access disabled, `az acr repository show` from outside the VNet is denied; read the digest from the run output. Hosting creation takes about 10 minutes and a Private Endpoint write can fail once with `InternalServerError`; a rerun of the same narrow module succeeded.

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

## Tailscale administration access

Tailscale is limited to approved synthetic-only administration of the private VM. Enrollment is a separate approved handoff, never part of `run.sh -x install`; keep auth keys out of the repo and shell history.

1. **Egress exception (Bicep).** Parameter `tailscale_egress` (default `false`) adds outbound NSG rules `tailscale-tcp` (443) and `tailscale-udp` (41641, 3478) to the `Internet` service tag. This is not an allowlist; the residual risk is accepted only for synthetic-only administration. Review it in what-if before enabling.
2. **Enroll the VM.** Export a one-time, tagged auth key only in your shell and pass it with `az vm run-command create ... --protected-parameters` so it is not stored in the command body. The script installs from tailscale.com, sets `net.ipv4.ip_forward=1` and runs:

   ```bash
   tailscale up --ssh --hostname <vm> --advertise-routes <vnet_cidr> --accept-dns=false
   ```

   Without a key, run `tailscale up` in the background, read the login URL from its log and open it. Each restart invalidates the URL.
3. **Approve in the tailnet.** Approve the advertised route, add an `ssh` ACL rule for the administrators, and add split DNS for the exact PoC hostnames only, resolved through a forwarder on the VM to Azure DNS `168.63.129.16`. Never override global service suffixes in a shared tailnet.

## Standing exceptions

Each exception needs a named owner and a review date recorded outside the repository; remove it when the review date passes without a renewal approval.

| Exception | Bound | Removal |
| --- | --- | --- |
| Tailscale egress (`tailscale_egress`) | Administration VM NSG, outbound 443/UDP 41641 and 3478 to the `Internet` tag, synthetic-only | Set `tailscale_egress = false` and deploy the narrow connectivity module after approval |
| Temporary operator grants | Single-resource scope on the AI account and Search service for the deployment operator | Commands in [Not created by Bicep](#not-created-by-bicep) |

## Not created by Bicep

ARM deployment creates the foundation (resource groups, network, NAT, administration VM, Azure OpenAI, Search, storage, DNS and Private Endpoints). These steps stay manual, native and separately approved; each section above has the commands:

| Not created | Where |
| --- | --- |
| CU defaults and analyzer | §2 CU defaults, §3 |
| Search index, data sources, skillset, indexers, knowledge source and base | §3 |
| Private-endpoint connection approvals | §3 |
| Entra API/SPA registrations, role assignments and consent | §4 |
| Container image build | §4 |
| Tailnet enrollment, routes and split DNS | [Tailscale administration access](#tailscale-administration-access) |
| Soft-deleted Cognitive Services names (purge before reusing a name after delete) | separate approval |

**Identity and data-plane handoff status (synthetic PoC):** the API registration, scope, roles, API service principal (assignment required) and user role assignments are created natively; only non-secret IDs are kept in ignored `.azure/checks/c/`. The payload modules have no `targetScope`, so emit them with an output-only `az deployment group create` in the foundation group. Remaining, in order:

1. After `scenario/hosting.bicep` reports the environment default domain, build `identity/spa-payload.bicep` outputs with the exact private HTTPS redirect, POST the SPA application, then run `identity/finalize-payloads.bicep` requests: PATCH the API with `preAuthorizedApplications` for the SPA (keep `identifierUris`, scope and roles as read back) and POST the SPA service principal.
2. CU defaults, analyzer and Search objects need data-plane rights on the AI account and Search service. The deployment's operator grants go to the *deployment caller* (`caller_principal_id`); any other principal (even subscription Owner) is denied. The Azure CLI operator received **temporary** single-resource grants (Cognitive Services User on the AI account; Search Index Data Contributor and Search Service Contributor on the Search service). Data-plane calls must originate from the administration VM through a managed `az vm run-command create` with the ephemeral token in `--protected-parameters` (never plain `--parameters`); pass it as `--protected-parameters T="$TOKEN"`, which the script reads as `$T`, and start the script with `test -n "$T"`. The JSON form `[{name:T,value:...}]` is accepted but silently delivers no parameter. Run one at a time, retry on `Conflict` and delete the run-command resource afterwards. A workstation resolving public addresses is refused. Tailscale is not part of this path. Revoke the grants after setup (`OPERATOR_OID` is the signed-in user's object ID):

   ```bash
   for role in "Cognitive Services User:$AI_ACCOUNT_ID" \
     "Search Index Data Contributor:$SEARCH_ID" "Search Service Contributor:$SEARCH_ID"; do
     az role assignment delete --assignee "$OPERATOR_OID" --role "${role%%:*}" --scope "${role#*:}"
   done
   ```

   Search skillset registration validates against the AI account and fails with `Public access is disabled` until `scenario/private-links.bicep` (Search shared private links to the AI account) is deployed and the target-side connections on the AI account and storage are approved (§3); check the Search-side links with `az search shared-private-link-resource list`. Register the skillset, both indexers, the knowledge source and base only after that.
3. Soft-deleted Cognitive Services accounts from a retired PoC: `az cognitiveservices account list-deleted`, then `az cognitiveservices account purge --location "$LOCATION" --resource-group "$OLD_RG" --name "$OLD_NAME"` for each exact name only, after review.

Before the first install, run what-if from an empty subscription. Check the administration VM image version (`az vm image list --sku server`) and VM size availability (`az vm list-skus`) in the approved region; set `vm_size` in the local parameters if the default `Standard_B2s` is restricted. What-if shows role assignments with runtime-computed names as `Unsupported`; that is expected and not a failure. Model deployments on one account are serialized (`@batchSize(1)`); parallel writes fail with `RequestConflict`.

**Cleanup:** source changes never delete cloud resources. Inventory only this PoC's resources under a separate approval, review dependencies and retention, and approve each deletion independently. Never use complete-mode deployment or rerun the initial VNet to clear old children.
