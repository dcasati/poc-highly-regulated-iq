# Native Bicep document-review deployment

This is the **new-solution, Terraform-independent** path for the private
document-review PoC. It does not deploy the inherited Fabric example. Copying
`infra/bicep/` and the application source is sufficient; no Terraform installation,
configuration, output, state store, import or Terraform-created resource is needed.
The currently deployed solution has a different owner. **Do not run this path over
it or infer permission to migrate it.** All examples are sanitized compiler fixtures,
not an approved target, executable configuration or evidence.

Use native `az deployment sub/group` commands, Microsoft Graph and the documented
service data-plane APIs. No AZD or infrastructure deployment wrapper is involved.
Initial foundation composition intentionally stops before operations requiring
identity propagation, target-owner approval or data-plane readback. Every later
`existing` reference is populated from this path's own created resources, unless
the operator deliberately chooses and separately verifies an existing boundary.

## Coverage and owners

| Boundary | Native owner / entry | Gate before next stage |
| --- | --- | --- |
| Three new resource groups, VNet, administration NSG/NIC/VM, controlled NAT | `infra/bicep/main.bicep` → connectivity | US/nonoverlapping ranges, approved destination-specific egress, SSH public key, pinned VM image; administrator enrolls VM separately |
| Endpoint subnet, Blob DNS and VNet link | `foundation/private-network.bicep` through `main.bicep` | No backend/state account prerequisite |
| Agent/runtime/build reservations, runtime/build NAT associations and NSGs | `foundation/network.bicep` through foundation | Agent has no NAT; runtime/build only approved exact destinations; deny-other-egress remains |
| Private application/agent Blob stores, Cosmos, private keyless Search, account, PEs/DNS | `foundation/main.bicep` through `main.bicep` | Private DNS/TLS/identity tests and propagation, not just successful ARM provisioning |
| Pinned US models and blocking native chat RAI policy | `foundation/main.bicep` | Regional Standard/US DataZoneStandard only; explicit versions/quota; verify declared filter pairs and chat association |
| Project identity, AAD connections, provisioning roles, native capability host | `foundation/project.bicep`, `provisioning.bicep`, `capability.bicep` | Each is separately ordered; host Succeeded within 30 minutes |
| Native file/intermediate/Cosmos runtime grants | `foundation/runtime-bindings.bicep` | Actual service-created stores and associated identities, never guessed names; separately revoke temporary Blob grant |
| CU supported-model defaults and hardened tools-disabled prompt agent/version | `foundation/bootstrap-payloads.bicep` + native REST | Preserve existing defaults/description/metadata; full native RAI policy ID; old agent versions retained |
| Runtime UAMI, private Premium ACR, four evidence containers and scoped roles | `scenario/platform.bicep` | Account/keyless Search/project grants and two read-only Search container grants; no browser direct service access |
| Search → Blob/CU processing/billing private links | Foundation Blob request + `scenario/private-links.bicep` | Inspect exact target/group pairs, target owners approve separately, serialize requests |
| Custom CU analyzer, PDF/JSON index/data sources/skillset/indexers/source/base | `knowledge/payloads.bicep` + `native/reconcile_knowledge.py` | Native ordered GET/PUT/readback, bounded analyzer polling; separately verify ingestion and US processing |
| Private build pool and immutable image | `acr-build/main.bicep` + native ACR Tasks | Approved source/base digest, private pool dependencies and build success; registry stays private/admin-disabled/bypass None |
| Internal ACA environment, literal PE, private DNS and peer encryption | `scenario/hosting.bicep` with `kind: 'container_apps'` | Correct endpoint NIC-backed DNS and private HTTPS; no public app/gateway IP |
| Single-tenant API/SPA, v2 delegated scope, PKCE and user roles | `identity/*-payload*.bicep` + native Graph | Real IDs; explicit directory authorization; no automatic Graph consent, user assignment or directory role |
| ACA digest workload and continuous worker | `scenario/runtime.bicep` | Identity, knowledge, agent, image and evidence acceptance; retained originals and human/case/owner review gates |
| Optional private artifact/state store | `state-backend/*` | Separate owner/approval; **never needed for this Bicep path** |

The legacy AKS entries remain only for their previously published contracts. Do
not use them for this solution; Container Apps is the chosen host.

## 1. Prepare and authorize a new target

Use one approved checkout/private operator host and its own existing authenticated
Azure CLI context throughout. Verify selected subscription, directory, caller object
ID and privileges without printing credentials. Registration permissions and scoped
RBAC creation rights must already be approved; this path never grants directory
roles or tenant-wide Graph consent to itself.

```sh
set +x
umask 077
mkdir -p .azure/checks
chmod 700 .azure/checks
```

Keep outputs/readbacks in owner-only ignored
`.azure/checks/bicep-parity-*.json`. Never save tokens or dump resource secrets.
Create ignored `infra/bicep/examples/<stage>.local.bicepparam` files using native
Bicep outputs and service readbacks, not a Terraform file. Require an explicit
US region and approved model version/SKU/quota. Resolve exact package/tailnet,
Container Apps and private-build dependency destinations; an empty egress fixture
is not operational. Review current Azure dependency requirements, resolve approved
IPv4 prefixes, and maintain them under change control. NAT alone does not authorize
egress. No `Internet`, `AzureCloud`, wildcard or all-address union is permitted.

Compile local parameters and run `tests/validate_parameters.py` before separately
reviewing native what-if and authorizing deployment. The documented offline suite
uses Bicep **0.44.1**; no live what-if/deployment is part of static validation.

```sh
az deployment sub what-if --name review-foundation --location "$US_REGION" \
  --template-file infra/bicep/main.bicep \
  --parameters infra/bicep/examples/main.local.bicepparam
# Only after explicit review/authorization of this exact new boundary:
az deployment sub create --name review-foundation --location "$US_REGION" \
  --template-file infra/bicep/main.bicep \
  --parameters infra/bicep/examples/main.local.bicepparam \
  --query properties.outputs --output json \
  > .azure/checks/bicep-parity-foundation.outputs.json
```

`main.bicep` creates all initial prerequisites. Its outputs hand off resource
groups, network/subnet/DNS IDs, created service names/endpoints and the RAI policy
ARM ID. No private backend is created or consulted. State-backend entries are
optional companion infrastructure, not part of the initial composition.

Do not blindly rerun initial VNet creation during resume: a parent VNet PUT can
reset child subnet configuration. Preserve successful resources and use the
ordered, boundary-specific entries below; review the complete native what-if for
any later network change. Do not run complete-mode deployments or delete
resources to recover from a failed stage.

Tailnet enrollment, routes/ACLs and **exact PoC hostname** split DNS are explicit
administrator actions. Never embed a tailnet key or configure global service-suffix
DNS in a shared tailnet. This synthetic-only administration transport is not a
FIPS attestation. Verify private Foundry/Search/Blob/Cosmos/ACR resolution and TLS
from the operator host. Public/unapproved-client access must fail.

## 2. Ordered native Foundry stages

For each entry, prepare its local parameters from the preceding Bicep/native
outputs, review `az deployment group what-if`, obtain separate approval, then use:

```sh
az deployment group create --resource-group "$FOUNDATION_RG" --name "$STAGE" \
  --template-file "$ENTRY" --parameters "$LOCAL_PARAMETERS" \
  --query properties.outputs --output json \
  > ".azure/checks/bicep-parity-${STAGE}.outputs.json"
```

1. `foundation/project.bicep`: actual account and deployment caller, with verified
   private connectivity. Outputs the project ID, system principal and native
   project endpoint.
2. `foundation/provisioning.bicep`: actual created agent Blob/Cosmos/Search names,
   returned endpoints and verified project identity association. Connections use
   AAD, contain no keys and are not shared. Wait for role propagation.
3. `foundation/capability.bicep`: actual three connection names, separate preview
   acceptance, successful private store access and scoped provisioning grants.
   Poll the exact returned host ARM ID using `2025-04-01-preview` for at most
   30 minutes; only `Succeeded` permits continuation. `Failed`, cancellation,
   unknown state, authorization/network error or timeout stops the stage.
4. Inspect the service-created agent Blob containers and Cosmos database using
   native private APIs. Inspect real identity associations. Populate
   `foundation/runtime-bindings.bicep` with those discovered names, actual project
   identity (included automatically), and only verified distinct extra principals.
   This stage never creates guessed native stores.
5. Verify retained container/database-scoped grants, then separately authorize
   deletion of **only** the provisioning output `temporary_blob_grant_id`:
   `az role assignment delete --ids "$TEMPORARY_BLOB_GRANT_ID"`. Confirm that exact
   assignment is not found, distinguishing 404 from access/network errors; confirm
   retained grants separately. Do not rerun provisioning afterward and restore it.

RBAC propagation/host provisioning do not establish extraction or inference.

### CU defaults and agent

Deploy the output-only `foundation/bootstrap-payloads.bicep` after reading CU
defaults and the selected/prebuilt analyzers' `supportedModels` with
`2025-11-01`. A defaults GET may report the specific unconfigured
`ModelDeploymentsNotConfigured` error on a new account; other errors are failures.
Supply preserved unrelated mappings. All five model/alias mappings must use the
verified supported pinned deployments; do not silently substitute a Global model
or unsupported completion-mini alias.

Materialize request **bodies** from the returned `properties.outputs` using local
JSON tooling. ARM compiler expressions are not REST bodies. Native execution:

For any output-only single request, the following offline extraction creates a
new owner-only body file without displaying it (set these three variables to the
selected stage's output file, output key and distinctive body filename):

```sh
python3 - "$OUTPUTS_FILE" "$REQUEST_KEY" "$BODY_FILE" <<'PY'
import json, sys
from pathlib import Path
outputs = json.loads(Path(sys.argv[1]).read_text())
body = outputs[sys.argv[2]]["value"]["body"]
with Path(sys.argv[3]).open("x") as destination:
    json.dump(body, destination)
PY
```

For defaults, `REQUEST_KEY=content_defaults_request`; for API registration,
`REQUEST_KEY=api_request`. Use the correct key for each other single request.
For the ordered Graph request array, extract each element's `body` individually
and execute its recorded `method`/`path`, not the entire array as one Graph body.
Do not overwrite an existing materialized file without inspecting it.

Native execution of the reviewed defaults body:

```sh
az rest --method patch \
  --url "${CONTENT_ENDPOINT%/}/contentunderstanding/defaults?api-version=2025-11-01" \
  --resource https://cognitiveservices.azure.com/ \
  --body @.azure/checks/bicep-parity-defaults.body.json \
  --output json > .azure/checks/bicep-parity-defaults-result.json
```

GET defaults again and compare every declared mapping while preserving unrelated
ones. Verify both CU custom-analyzer and native layout processing stay US-only.

For the agent, GET the selected project's `/agents` and
`/agents/<name>/versions?api-version=2025-11-15-preview` first. An existing agent
is not replaced/deleted. Supply its reviewed description/metadata and optional
prompt-definition settings as `preserved_agent`; omit server-owned IDs/version
timestamps/status fields. Use `agent_request` to POST a **new version** only when
the reviewed definition differs. For a missing agent, use `new_agent_request` to
POST `/agents`. Native audience is `https://ai.azure.com/`, not the ARM audience.
Earlier versions remain intact.

The Bicep-owned `foundation/review-agent.instructions.txt` restricts the entire
request to current case evidence, refuses mixed/unrelated tasks and forbids tools.
Read back the new enabled version, exact model, instructions, empty tools, preserved
metadata/description and `definition.rai_config.rai_policy_name` equal to the
**full native RAI ARM ID**. The model also references the blocking native policy.
Compare declared filter name/source pairs, not all GET fields: Azure adds
Defender/tool-stage defaults. Never disable protections to remove those defaults.
Task Adherence is deliberately absent because its documented processing may
leave the US.

Use `/openai/v1/responses` for a synthetic **in-scope evidence-review** smoke test,
with the verified `agent_reference` name/version, `tool_choice: "none"`,
`store: false`, no shared conversation and current synthetic `ref_id` evidence.
Require `completed`, evidence-supported output and no tool activity. Also verify
an unrelated/mixed request receives the documented whole-request refusal.
Do not ask the hardened agent for an out-of-scope connectivity marker. Record
request storage controls even if the response omits the `store` echo. These tests
do not establish service retention or application chat readiness.

## 3. Scenario platform, shared links and knowledge

Deploy `scenario/platform.bicep` in the new scenario group using the Bicep-owned
application Storage/Search/account/project references and endpoint/registry-DNS
IDs. Capture real UAMI client/principal/resource IDs and registry name/login server.
Four separate containers retain originals, review state, approved PDFs and
reviewed JSON evidence. Search receives reader only on the last two; app and
project grants never become browser permissions.

Run `scenario/private-links.bicep` in **Search's** resource group. Inspect each
existing target/group pair first; supply existing names to avoid duplicate requests.
The account links are `foundry_account` (processing) and
`cognitiveservices_account` (billing), in addition to the foundation Blob link.
Target owners inspect the exact pending private endpoint connections and approve
only the intended requests:

```sh
az network private-endpoint-connection approve --id "$VERIFIED_CONNECTION_ID" \
  --description "Separately approved private document-review dependency"
```

This is an explicit owner action, not a Bicep auto-approval. Verify both target-side
Approved and Search-side Succeeded for all three dependencies, with bounded
polling (30 minutes, terminal failure stops). Never enable trusted-service bypass
or public endpoints to fix connectivity.

Deploy `knowledge/payloads.bicep` in output-only mode with the reviewed custom
analyzer fields, actual endpoints/model names, `geography` or `dataZone`, and
verified private dependencies. Match `application.field_names` to this schema.
Save `properties.outputs` as `.azure/checks/bicep-parity-knowledge.outputs.json`.

The focused native reconciler owns exactly these nine data-plane objects, not
infrastructure deployment. It uses ephemeral Entra tokens in memory, trusted TLS,
no redirects, same-origin asynchronous polling, declared-property GET comparison,
conditional updates where the service returns an ETag, and a 30-minute analyzer
poll budget. No credentials are parameters or outputs.

```sh
# Read-only compare first; missing/drifted objects are an intentional nonzero result.
python3 infra/bicep/native/reconcile_knowledge.py \
  --outputs .azure/checks/bicep-parity-knowledge.outputs.json \
  --content-endpoint "$CONTENT_ENDPOINT" --search-endpoint "$SEARCH_ENDPOINT"
# After separate approval of these exact owned object writes:
python3 infra/bicep/native/reconcile_knowledge.py \
  --outputs .azure/checks/bicep-parity-knowledge.outputs.json \
  --content-endpoint "$CONTENT_ENDPOINT" --search-endpoint "$SEARCH_ENDPOINT" \
  --approve-write
```

Existing differing custom analyzers require the additional explicitly reviewed
`--replace-analyzer`. Search order is index → PDF/JSON data sources → layout
skillset → PDF/JSON indexers → knowledge source → knowledge base. Each write is
followed by GET comparison; matching objects are not rewritten. A failure stops
the sequence and preserves prior successful objects. Service-added defaults are
not fought. This is registration/configuration evidence, **not ingestion readiness**.

Run both private indexers with native `POST /indexers/<name>/run` and inspect
`GET /indexers/<name>/status?api-version=2026-08-01-preview` under a bounded budget.
Require no failed items, success and nonempty synthetic approved PDF and reviewed
JSON evidence. Verify page references, case/owner filterability and source/base
retrieval using the authenticated application's enforced filters. Unfiltered
knowledge/MCP access is not an authorization boundary.

For separately authorized replacement/teardown: rebuild/delete the base before
its source when source identity/kind changes; delete indexers before skillset/data
sources/index. Inspect names/ETags first. Do not delete native-generated assets or
original evidence. This path does not implement destructive teardown automation.

## 4. Private build and Container Apps hosting

If a private build is needed, deploy `acr-build/main.bicep` in the registry group
with the created dedicated build subnet, same US region and verified dependencies.
Wait for pool Succeeded and at least one instance. Then run the native build on
that pool only, supplying the separately approved immutable runtime/base image:

```sh
az acr build --registry "$REGISTRY_NAME" --agent-pool "$AGENT_POOL_NAME" \
  --image review-portal:reviewed-build --file app/ReviewPortal/Dockerfile \
  --build-arg "RUNTIME_IMAGE=$APPROVED_RUNTIME_IMAGE_DIGEST" app/ReviewPortal
```

Inspect native build logs privately, verify completion and query the registry's
actual image digest. Deployment uses `review-portal@sha256:<verified-digest>`,
never the temporary tag. No local/public ACR worker, registry key/admin user,
public-access exception or bypass is permitted. Alternatively use a separately
verified immutable image already built into this Bicep-owned registry through
an approved private path. The pool is optional only in that case.

Deploy `scenario/hosting.bicep` with `hosting: { kind: 'container_apps' }`,
actual runtime/endpoint subnets, VNet and platform names. Verify public networking
Disabled, internal environment, PE `managedEnvironments`, peer encryption enabled,
regional Private Link DNS and default-domain wildcard resolving to the **actual PE
NIC**, not the environment ILB. Outbound-only NAT public IPs are not app ingress.
Private endpoints have additional ACA management/PE/DNS charges; obtain cost approval.

The returned `container_apps_default_domain` permits preparation of the deterministic
app's expected private HTTPS redirect URI before runtime creation. This is not a
deployed portal URL. Verify the actual runtime FQDN afterward and update the SPA
redirect if the service's returned name differs.

## 5. Native single-tenant Entra registration

Use the selected directory and approved native Graph permissions. These entries
emit reviewable Graph bodies only; creating ARM output deployments does **not**
create applications. Search existing registrations by exact selected display
name first and stop on duplicates/conflicting ownership. On resume, GET exact
created object IDs and compare; never repeat POST blindly.

Each identity payload requires the explicit approved `tenant_id` and returns
`expected_tenant_id`. Before any Graph operation, require the selected account
directory to equal that output:

```sh
test "$(az account show --query tenantId --output tsv)" = "$EXPECTED_TENANT_ID"
```

1. `identity/api-payload.bicep` emits API POST `/v1.0/applications`: single tenant,
   v2 access tokens, delegated `access_as_user`, deterministic user-only Caseworker
   and Reviewer roles, explicit owner. Save native returned **object `id` and
   application `appId` separately**.
2. `identity/spa-payload.bicep` uses that API `appId` and the exact approved private
   HTTPS redirect URI. Its POST creates the SPA, declares only the custom API
   scope and disables implicit flow. The unchanged browser uses authorization
   code **PKCE**, not a client secret.
3. `identity/finalize-payloads.bicep` PATCHes the API identifier URI and preauthorizes
   **only that SPA** for the custom scope. It creates API/SPA service principals;
   the API has `appRoleAssignmentRequired: true`. Compare API scope/roles on GET
   after PATCH; preserve them and stop on any drift. No Graph scope is requested.

Execute reviewed bodies with native Graph, capturing results privately:

```sh
az rest --method post --url https://graph.microsoft.com/v1.0/applications \
  --resource https://graph.microsoft.com/ \
  --body @.azure/checks/bicep-parity-api.body.json \
  --output json > .azure/checks/bicep-parity-api-created.json
```

Apply the corresponding SPA/Graph PATCH/SP requests individually in the emitted
order, using their materialized bodies and actual IDs. API preauthorization is
itself a separately approved administrator decision; this path does not grant
tenant-wide consent. Any organization-required consent remains an explicit
administrator operation.

User assignment is **not emitted or executed automatically**. After separate
approval, an administrator may POST
`/v1.0/servicePrincipals/<api-service-principal-object-id>/appRoleAssignments`
with `{principalId: <approved-user-object-id>, resourceId:
<api-service-principal-object-id>, appRoleId: <Caseworker-or-Reviewer-role-id>}`.
Caseworkers get Caseworker; reviewers require **both** roles. These are application
roles, never directory roles. Verify tenant/audience/scope/role claims and rejection
of wrong/expired/unsigned tokens. Users get no direct Search/storage/Foundry access;
case ownership uses the authenticated tenant object ID, never a client-supplied ID.

## 6. Runtime and acceptance

Deploy `scenario/runtime.bicep` only after real SPA/API IDs, supported CU/analyzer
fields, verified tools-disabled agent, successful knowledge/identity acceptance,
private image digest and transport/platform evidence are available. Output
`portal_url` comes only from the created app's actual ingress FQDN. Verify trusted
private HTTPS, managed-identity private pulls/data access, one continuously running
worker, health endpoints, public-path denial and peer encryption.

Default safe mode requires accepted **FIPS 140-3 encryption-path evidence**.
Only explicit synthetic-PoC authorization permits
`attestation_mode: 'synthetic_poc_attestation_deferred'`, `approved: false` and
all three encryption evidence strings exactly empty. The output is deferred/not
certified, not production readiness. It does not waive private networking, US
processing, real identity, digest, retained evidence, human confirmation or
case/owner isolation. A FIPS node/image flag, algorithm or successful deployment
is not certification.

Use synthetic documents first. Verify every field needs human confirmation,
low/unknown confidence and missing data are visible, only a Reviewer can publish,
stale/partial reviews fail, originals remain retained, no content is searchable
before approval, both evidence paths become searchable afterward, and foreign
cases/owners cannot be retrieved or cited. Test backup/recovery and any approved
locked retention policy separately. Never lock/delete evidence implicitly.

Preview availability, model quota, DNS/RBAC propagation, supported CU/layout US
processing, native Entra consent, private build dependencies, locked retention,
cryptographic acceptance and end-to-end chat readiness require real operator
evidence. Compilation and current-owned-resource readback do not prove a fresh
recreation. Isolated service calls do not establish complete browser-workflow readiness.
