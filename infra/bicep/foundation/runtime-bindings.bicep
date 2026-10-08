import { approval } from '../types.bicep'
@description('Existing account and project child names.')
param foundry { account: string, project: string }
@description('Existing foundation agent storage, Cosmos and Search names.')
param stores { blob: string, cosmos: string, search: string }
@description('Discovered native-generated names. Never construct names or create these stores.')
param discovered { files_container: string, intermediate_container: string, database_name: string }
@description('Verified extra service runtime principals; actual project system identity is included automatically. Exclude duplicates.')
param extra_principal_ids string[] = []
@description('Capability host Succeeded, project association, store existence and documented runtime-role verification.')
param runtime_bindings approval

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = { name: foundry.account }
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = { parent: account, name: foundry.project }
var principals = concat([project.identity.principalId], extra_principal_ids)
module blob_roles '../modules/storage-bindings.bicep' = [for i in range(0, length(extra_principal_ids) + 1): {
  name: 'agent-container-roles-${i}'
  params: {
    account_name: stores.blob
    create_containers: false
    bindings: [
      { container_name: discovered.files_container, principal_id: principals[i], principal_type: 'ServicePrincipal', role_id: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' }
      { container_name: discovered.intermediate_container, principal_id: principals[i], principal_type: 'ServicePrincipal', role_id: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' }
    ]
  }
}]
module data_roles '../modules/cosmos-data-role.bicep' = [for i in range(0, length(extra_principal_ids) + 1): {
  name: 'agent-database-role-${i}'
  params: { account_name: stores.cosmos, database_name: discovered.database_name, principal_id: principals[i] }
}]
module model_roles '../modules/service-roles.bicep' = [for i in range(0, length(extra_principal_ids) + 1): {
  name: 'agent-model-role-${i}'
  params: { kind: 'foundry', name: account.name, principal_id: principals[i], role_id: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' }
}]
module blob_control '../modules/service-roles.bicep' = {
  name: 'agent-storage-control'
  params: { kind: 'storage', name: stores.blob, principal_id: project.identity.principalId, role_id: '17d1049b-9a84-46fb-8f53-869881c3d3ab' }
}
module search_service '../modules/service-roles.bicep' = [for (principal, i) in extra_principal_ids: {
  name: 'extra-search-service-${i}'
  params: { kind: 'search', name: stores.search, principal_id: principal, role_id: '7ca78c08-252a-4471-8644-bb5ff32d4ba0' }
}]
module search_data '../modules/service-roles.bicep' = [for (principal, i) in extra_principal_ids: {
  name: 'extra-search-data-${i}'
  params: { kind: 'search', name: stores.search, principal_id: principal, role_id: '8ebe5a00-799e-43f5-93ac-243d3dce84a7' }
}]
output verification_reference string = runtime_bindings.evidence_reference
output bootstrap_revocation_required bool = true
