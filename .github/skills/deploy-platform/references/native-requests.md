# Native requests for guided DEV deployment

Read this after choosing the derived repository, execution host and delegated user. This is a request reference, not an executable deployment wrapper. Keep Terraform as the infrastructure owner and use Fabric's native Git and notebook APIs.

## Contents

- [Authentication and response receipts](#authentication-and-response-receipts)
- [Git connection and synchronization](#git-connection-and-synchronization)
- [Operation and notebook completion](#operation-and-notebook-completion)
- [Resolve and verify target bindings](#resolve-and-verify-target-bindings)
- [Knowledge readiness and retrieval](#knowledge-readiness-and-retrieval)

## Authentication and response receipts

Use `az rest --resource https://api.fabric.microsoft.com` for ordinary reads. For requests that can return `202`, capture the **status, response headers and body**: Azure CLI's normal JSON body alone does not provide the operation receipt. Do not enable debug/verbose HTTP logging to obtain headers.

For a reviewed POST, use this shell pattern with the known Fabric URL and a non-secret JSON request file. Supply the bearer header through curl's stdin configuration, not an expanded token in process arguments. Run on the execution host with shell tracing off:

```bash
set +x
set -euo pipefail
case "$request_url" in
  https://api.fabric.microsoft.com/v1/*) ;;
  *) printf 'Unexpected Fabric request origin\n' >&2; exit 1 ;;
esac
response_dir="$(mktemp -d)"
printf 'Response receipt directory: %s\n' "$response_dir"
token="$(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken --output tsv)"
printf 'header = "Authorization: Bearer %s"\n' "$token" |
  curl --config - --silent --show-error --fail-with-body \
    --connect-timeout 15 --max-time 120 \
    --request POST --header 'Content-Type: application/json' \
    --data-binary "@$request_file" \
    --dump-header "$response_dir/headers" \
    --output "$response_dir/body.json" --write-out '%{http_code}\n' \
    "$request_url"
unset token
```

Use a separate, private scratch directory per request. Read only the needed result/error fields, retain non-secret operation/job IDs in session artifacts, and clean up the response files when no longer needed. Do not print entire headers, tokens, claims or provider debug logs. Do not follow redirects or send authorization to a `Location`/continuation URL without verifying the expected Fabric origin and target path.

Do not blindly retry POSTs after network timeouts: the server may already have accepted the operation. Inspect its receipt/current status first. For `429`, honor `Retry-After`; retry read-only polling transient failures within the phase deadline. Treat unexpected status/error codes as failures, not empty successful responses.

## Git connection and synchronization

Use `dev_workspace_id` and `github_connect_request` from Terraform output, not a display-name guess. Resolve the plan logical ID from the **reviewed** `workspace/Bootstrap.DeploymentPlan/.platform`.

| Step | Native request | Handling |
| --- | --- | --- |
| Inspect connection | `GET /v1/workspaces/{workspaceId}/git/connection` | Inspect `gitConnectionState` and compare repository/branch/directory with the intended target. Require full, not selective, synchronization. |
| Connect if `NotConnected` | `POST /v1/workspaces/{workspaceId}/git/connect` | Use the Terraform `github_connect_request` JSON unchanged; it contains the configured connection ID, not the PAT. |
| Check caller's Git credentials | `GET /v1/workspaces/{workspaceId}/git/myGitCredentials` | If missing, use the documented PATCH on the same endpoint with `source: "ConfiguredConnection"` and the approved `connectionId`. Do not disconnect the workspace. |
| Initialize if `Connected` | `POST /v1/workspaces/{workspaceId}/git/initializeConnection` | Use `{"initializationStrategy":"PreferRemote"}` only after confirming the intended incoming content; poll if asynchronous. |
| Inspect synchronized workspace | `GET /v1/workspaces/{workspaceId}/git/status` | Read the current head, remote commit and changes, polling if asynchronous. Stop for conflicts/deletions or concurrent authoring. |
| Update when required | `POST /v1/workspaces/{workspaceId}/git/updateFromGit?beta=true` | Attach the plan in the full request below, after reviewing the exact incoming revision. |

For Initialize Connection, handle every `requiredAction`: `UpdateFromGit` continues; `None` needs no sync; `CommitToGit` or an unknown value stops for review. Initialize Connection itself cannot accept a plan.

After explicit approval of the incoming definitions, construct the following body with `jq`/JSON serialization, using the actual returned head and reviewed remote SHA:

```json
{
  "workspaceHead": "<returned-workspace-head>",
  "remoteCommitHash": "<reviewed-full-remote-commit-sha>",
  "options": {
    "allowOverrideItems": true,
    "deploymentPlan": {
      "logicalId": "<Bootstrap-logical-id-from-reviewed-platform-file>",
      "referenceType": "ByLogicalId"
    }
  }
}
```

`workspaceHead` may be JSON `null` only immediately after initialization when that is what Fabric returned. Do not use the string `"null"` or omit a required current head on later updates. Refuse an unexpected remote SHA. Omit `conflictResolution` rather than silently choosing `PreferRemote`; `allowOverrideItems` is explicit consent to apply reviewed incoming definitions, not permission to discard conflicts or delete data.

If already `ConnectedAndInitialized`, reuse the connection. If the desired SHA is already synchronized and only expected generated binding changes remain, inspect/reuse the live binding instead of overwriting it. On a no-op Git update, notebook actions are not guaranteed to run.

References: [Connect](https://learn.microsoft.com/rest/api/fabric/core/git/connect), [Get connection](https://learn.microsoft.com/rest/api/fabric/core/git/get-connection), [Update my Git credentials](https://learn.microsoft.com/rest/api/fabric/core/git/update-my-git-credentials), [Initialize](https://learn.microsoft.com/rest/api/fabric/core/git/initialize-connection), [Status](https://learn.microsoft.com/rest/api/fabric/core/git/get-status), [Update](https://learn.microsoft.com/rest/api/fabric/core/git/update-from-git), [plan extension](https://learn.microsoft.com/fabric/cicd/deployment-plan/deployment-plan-automation).

## Operation and notebook completion

For a Fabric operation's `202`, retain `x-ms-operation-id`, validated `Location` and `Retry-After`. Poll `GET /v1/operations/{operationId}` until `Succeeded`; continue only for `NotStarted`/`Running`, honor polling delays and fail on unsuccessful/unknown states. Read `/result` when the operation provides a result, including Initialize Connection and Get Status. Do not turn a missing/non-JSON result for a no-body operation into an empty JSON object.

A deployment plan failure can leave earlier groups completed. Inspect the operation result and notebook runs before resuming. Never submit a duplicate while another operation/job is active.

When an already-deployed notebook genuinely needs running outside the plan, use its **physical item ID** with:

```http
POST https://api.fabric.microsoft.com/v1/workspaces/{workspaceId}/notebooks/{notebookId}/jobs/execute/instances?jobType=RunNotebook
```

Use the notebook-specific route and `RunNotebook` job type from the notebook API guide; the deployment plan's `job.type: Execute` is not a scheduler job type to copy blindly. For the untouched sample, omit the body and use the notebook's parameter defaults; run `SeedScenario` to completion, then `BindScenario`. Do not invent a default lakehouse attachment. For customized parameters, follow the notebook API's supported `executionData` shape, not an assumed generic `parameters` property.

This job API returns a **job-instance Location**, not a generic `/operations/{id}` receipt. Validate its workspace/item, honor `Retry-After`, and poll that instance until `Completed`. `Failed`, `Cancelled`, a timeout or an unknown status does not satisfy readiness. Inspect non-secret failure details and preserve the receipt. A phase observation timeout does not cancel the running cloud operation.

References: [LROs](https://learn.microsoft.com/rest/api/fabric/articles/long-running-operation), [run item job](https://learn.microsoft.com/rest/api/fabric/core/job-scheduler/run-on-demand-item-job), [get job instance](https://learn.microsoft.com/rest/api/fabric/core/job-scheduler/get-item-job-instance), [notebook execution](https://learn.microsoft.com/fabric/data-engineering/notebook-public-api).

## Resolve and verify target bindings

Enumerate `GET /v1/workspaces/{devWorkspaceId}/items`, following pagination. Use `.platform` identities and current display names/types to resolve the intended items; require unique matches, then read their type-specific metadata. Do not select the first name match in another workspace.

Read the lakehouse metadata and the new-experience ontology metadata/definition. Get Definition can itself be asynchronous. Check the current workspace, expected ontology logical ID/generation and source bindings against `docs/ontology-knowledge.md`. Decode definition parts locally; do not rewrite TMDL from this deployment skill.

Require the successful binder's scoped SQL refresh and current-workspace lakehouse/SQL pins. Git-normalized zero GUIDs, logical IDs and placeholder workspace names are not runtime source IDs. Discover the physical lakehouse and ontology GUIDs only from this DEV target before calling `scripts/configure_knowledge.py`.

## Knowledge readiness and retrieval

Use Terraform's status URL, Search endpoint, knowledge-base name and `ontology_knowledge_sources` outputs. Use the API version from the deployed configuration, not a guessed newer preview version.

The deployer receives `Search Index Data Reader`; Azure resource ownership by itself would not grant query data access. Acquire the signed-in user's token for `https://search.azure.com` in memory. The same user token can authenticate the direct Search call and supply `x-ms-query-source-authorization`, provided the user has Search and Fabric access and the required delegated consent. Do not use a service-principal token as that end-user identity.

Pass both headers using the same stdin-config technique, only to the verified Search endpoint:

```bash
printf 'header = "Authorization: Bearer %s"\nheader = "x-ms-query-source-authorization: %s"\n' \
  "$search_user_token" "$search_user_token" |
  curl --config - --silent --show-error --fail-with-body \
    --connect-timeout 15 --max-time 120 \
    --request POST --header 'Content-Type: application/json' \
    --data-binary "@$retrieval_request_file" \
    --output "$retrieval_response_file" "$verified_retrieve_url"
```

Merge the following source parameters into the `messages` request in `docs/ontology-knowledge.md`, using the actual ontology knowledge-source name:

```json
{
  "knowledgeSourceParams": [
    {
      "kind": "fabricOntology",
      "knowledgeSourceName": "<actual-ontology-knowledge-source-name>",
      "includeReferences": true,
      "includeReferenceSourceData": true
    }
  ]
}
```

Require a successful `activity` entry of type `fabricOntology`, a `references` entry of the same type with matching DEV `workspaceId`/`ontologyId`, and `sourceData.fabricRawData` grounded in the bound tables. A document-only answer is a failed ontology check.

Check the indexed file source separately, using a documentation/background question and the actual document source name. Its parameter discriminator is `kind: "indexedOneLake"`, not `searchIndex`; request references/source data there too. Require successful ingestion and a reference from that source. Preserve denied/failed-source errors instead of accepting partial answers as fully ready. Never persist either token in config, state, request JSON or logs.

References: [Fabric ontology retrieval and response fields](https://learn.microsoft.com/azure/search/agentic-knowledge-source-how-to-fabric-ontology#query-a-knowledge-base), [ontology runtime parameters](https://learn.microsoft.com/javascript/api/@azure/search-documents/fabricontologyknowledgesourceparams?view=azure-node-preview), [OneLake runtime parameters](https://learn.microsoft.com/javascript/api/@azure/search-documents/indexedonelakeknowledgesourceparams?view=azure-node-preview).
