import { approval } from '../types.bicep'
@description('Existing foundation account.')
param account_name string
@description('Existing project child name.')
param project_child_name string
@description('Existing foundation agent Storage, Cosmos and Search names in this resource group.')
param stores { blob: string, cosmos: string, search: string }
@description('Discovered endpoints, not guessed service/project URLs.')
param endpoints { blob: string, cosmos: string, search: string }
@description('Verified project identity association and reviewed connection/grant targets.')
param provisioning approval
resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = { name: account_name }
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = { parent: account, name: project_child_name }
resource blob 'Microsoft.Storage/storageAccounts@2025-06-01' existing = { name: stores.blob }
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2025-04-15' existing = { name: stores.cosmos }
resource search 'Microsoft.Search/searchServices@2025-05-01' existing = { name: stores.search }
var definitions = [
  { name: stores.blob, category: 'AzureStorageAccount', target: endpoints.blob, id: blob.id }
  { name: stores.cosmos, category: 'CosmosDb', target: endpoints.cosmos, id: cosmos.id }
  { name: stores.search, category: 'CognitiveSearch', target: endpoints.search, id: search.id }
]
resource connections 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = [for item in definitions: {
  parent: project
  name: item.name
  properties: {
    category: item.category
    target: item.target
    authType: 'AAD'
    isSharedToAll: false
    metadata: union(
      { ApiType: 'Azure', ResourceId: item.id, location: account.location, verification: provisioning.evidence_reference },
      item.category == 'CognitiveSearch' ? { ApiVersion: '2025-05-01-preview' } : {}
    )
  }
}]
var grants = [
  { kind: 'storage', name: stores.blob, role: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' }
  { kind: 'cosmos', name: stores.cosmos, role: '230815da-be43-4aae-9cb4-875f7bd000aa' }
  { kind: 'search', name: stores.search, role: '7ca78c08-252a-4471-8644-bb5ff32d4ba0' }
  { kind: 'search', name: stores.search, role: '8ebe5a00-799e-43f5-93ac-243d3dce84a7' }
]
module roles '../modules/service-roles.bicep' = [for (grant, i) in grants: {
  name: 'provisioning-role-${i}'
  params: { kind: grant.kind, name: grant.name, principal_id: project.identity.principalId, role_id: grant.role }
}]
output temporary_blob_grant_id string = extensionResourceId(blob.id, 'Microsoft.Authorization/roleAssignments', guid(blob.id, project.identity.principalId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'))
output connection_names object = { blob: connections[0].name, cosmos: connections[1].name, search: connections[2].name }
