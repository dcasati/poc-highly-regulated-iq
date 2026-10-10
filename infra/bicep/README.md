# Bicep module reference

`infra/bicep/` is the canonical infrastructure source. Use Bicep and Azure CLI
from Bash.
The operator procedure is in [getting started](../../docs/getting-started.md).

## Default template and inputs

`main.bicep` is the subscription-scoped default for the root `run.sh`. It creates
connectivity, foundation and scenario resource groups, a private administration
VM, VNet, controlled outbound-only NAT, reserved subnets, Private DNS/Endpoints,
keyless application Storage/Search/AI Services and explicit model deployments.
It does **not** create the portal, directory registrations or data-plane assets.

All initial inputs are explicit: `project_name`, `location`, `vnet_cidr`,
`administration`, `ssh_public_key`, `image_version`, `administration_egress`,
`platform_destinations`, `models`, `caller_principal_id`,
`caller_principal_type`. `examples/main.example.bicepparam` is a credential-free
shape example, not an approval or deployable configuration. Replace all examples
with verified values, pin the VM/model versions and review each egress destination.
The region type allows supported US regions; model SKUs allow only `Standard`
or `DataZoneStandard`, never Global. Availability and each processing boundary
still require separate verification.

## Modules and explicit handoffs

| Entry | Responsibility / prerequisite |
| --- | --- |
| `connectivity/main.bicep` | Private SSH-key-only administration VM and network/NAT; no public NIC or automatic tailnet enrollment. |
| `foundation/private-network.bicep`, `network.bicep` | Reserved endpoint, delegated Container Apps runtime and build subnets; DNS links and destination-restricted NSGs. NAT attaches to administration/runtime/build only. |
| `foundation/main.bicep` | Private services, model/RAI policy and scoped caller grants; creates a Search Blob link **request**, not target-owner approval. |
| `foundation/bootstrap-payloads.bicep` | Reviewable CU-default PATCH preserving unrelated model mappings. No agent objects; emits requests only. |
| `identity/*.bicep` | Reviewable single-tenant SPA/API Graph payloads. Role assignment and delegated consent remain separate operator actions. No secrets or automatic consent. |
| `scenario/platform.bicep`, `private-links.bicep` | Private registry, application identity, application-owned containers/grants and missing shared-link requests. Existing links are not recreated; approval remains target-owner action. |
| `knowledge/payloads.bicep` | Reviewable CU analyzer and eight ordered Search PUT requests. No fake ARM data-plane resources or automatic ingestion. |
| `acr-build/main.bicep` | Optional private-registry VNet-connected build pool; no registry/network ownership or access-setting changes. |
| `scenario/hosting.bicep` | Only private Container Apps hosting with its Private Endpoint and DNS. Requires reviewed runtime/endpoint/VNet references and `hosting_dependencies`. |
| `scenario/runtime.bicep` | Digest-pinned portal after real browser registrations, knowledge readiness and reviewed image. Accepts `platform`, `runtime`, `application`, branding and region. |
| `modules/`, `types.bicep` | Reusable typed network, storage and least-privilege role contracts. |

Use outputs from the selected deployment as subsequent inputs, not guessed IDs
or another project's resources. Native Graph, CU and Search requests use
separately reviewed `az rest` operations with the correct service audience/API
version. GET and compare owned objects before PUT/PATCH; preserve unrelated
settings, review drift and ownership, honor bounded asynchronous polling and
check readiness. Registration success is not ingestion/query success.
No Python deployment reconciler or silent approval automation is supplied.

## Synthetic runtime contract and private access

The runtime example uses the explicitly authorized synthetic-only
`synthetic_poc_attestation_deferred` mode: `approved: false` and
`platform_evidence`, `image_evidence`, `transport_evidence` exactly `''`.
It is deferred/not certified, not production-ready. The discriminated
`evidence_gated` mode remains available for a separately accepted evidence record.
Neither mode relaxes immutable image, real SPA/API identity, approved knowledge,
private endpoints, TLS/encryption controls, processing boundaries or human review.

Storage, Search, AI Services, registry and Container Apps disable public
network access; bypass stays `None`, registry admin stays disabled. The sole
public IP is attached to controlled outbound NAT, never the VM, application or
ingress gateway. Exact reviewed egress rules do not authorize Internet-wide access.

**Existing-resource safety:** source cleanup is not a migration. Preserve local
state/configuration and cloud resources. Do not deploy over resources this PoC
does not own without an explicit reviewed ownership change; matching names do not
establish ownership or make Bicep an import mechanism.

Direct inference uses `application.openai_endpoint` / `chat_deployment`
(`Portal__OpenAIEndpoint` / `Portal__ChatDeployment`), not project or agent
bindings. The API calls `/openai/v1/chat/completions` with the deployment name,
`https://ai.azure.com/.default` inference scope and no tools; CU retains the
Cognitive Services scope. Verify the inference audience against the selected
private endpoint during the authorized readiness handoff. Keep the private administration VM
unless an approved alternate private host and route/DNS path are demonstrated.
Managed-agent source removal does not delete any existing cloud resources;
cleanup and role revocation require separate approved inventory/retention review.

## Offline checks

With the documented Bicep compiler available, run:

```bash
python3 -m unittest discover -s infra/bicep/tests -p 'test_*.py'
```

Tests compile every module/example, enforce API request shapes and the runtime,
identity, private networking and egress contracts. They make no cloud calls.
`tests/validate_parameters.py` supplies additional offline semantic checks for
compiled parameter JSON; example mode is only for test fixtures.
Static success does not prove permissions, quota, preview availability or readiness.
