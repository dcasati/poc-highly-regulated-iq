@description('Existing resource kind for the target-scoped grant.')
@allowed(['storage', 'search', 'foundry', 'cosmos', 'registry', 'network', 'cluster'])
param kind string
@description('Existing top-level resource name. Project grants use the separate parent/child module.')
param name string
@description('Reviewed principal GUID, never a credential.')
param principal_id string
@description('Built-in role definition GUID; operator must verify the intended narrow role.')
@allowed([
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  '230815da-be43-4aae-9cb4-875f7bd000aa'
  '17d1049b-9a84-46fb-8f53-869881c3d3ab'
  '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  '1407120a-92aa-4202-b7e9-c0e197c71c8f'
  'a97b65f3-24c7-4388-baec-2e87135dc908'
  '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  '4d97b98b-1d4f-4787-a291-c67834d212e7'
  'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b'
])
param role_id string
@description('Deployment caller or managed identity type.')
@allowed(['User', 'ServicePrincipal'])
param principal_type string = 'ServicePrincipal'

resource storage 'Microsoft.Storage/storageAccounts@2025-06-01' existing = if (kind == 'storage') { name: name }
resource search 'Microsoft.Search/searchServices@2025-05-01' existing = if (kind == 'search') { name: name }
resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = if (kind == 'foundry') { name: name }
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2025-04-15' existing = if (kind == 'cosmos') { name: name }
resource registry 'Microsoft.ContainerRegistry/registries@2025-04-01' existing = if (kind == 'registry') { name: name }
resource network 'Microsoft.Network/virtualNetworks@2024-05-01' existing = if (kind == 'network') { name: name }
resource cluster 'Microsoft.ContainerService/managedClusters@2025-05-01' existing = if (kind == 'cluster') { name: name }

var properties = {
  principalId: principal_id
  principalType: principal_type
  roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role_id)
}
resource storage_role 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (kind == 'storage') {
  name: guid(storage.id, principal_id, role_id)
  scope: storage
  properties: properties
}
resource search_role 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (kind == 'search') {
  name: guid(search.id, principal_id, role_id)
  scope: search
  properties: properties
}
resource foundry_role 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (kind == 'foundry') {
  name: guid(foundry.id, principal_id, role_id)
  scope: foundry
  properties: properties
}
resource cosmos_role 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (kind == 'cosmos') {
  name: guid(cosmos.id, principal_id, role_id)
  scope: cosmos
  properties: properties
}
resource registry_role 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (kind == 'registry') {
  name: guid(registry.id, principal_id, role_id)
  scope: registry
  properties: properties
}
resource network_role 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (kind == 'network') {
  name: guid(network.id, principal_id, role_id)
  scope: network
  properties: properties
}
resource cluster_role 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (kind == 'cluster') {
  name: guid(cluster.id, principal_id, role_id)
  scope: cluster
  properties: properties
}
