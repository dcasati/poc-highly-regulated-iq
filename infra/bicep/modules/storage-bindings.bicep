@description('Existing storage account; this module never changes account settings.')
param account_name string
@description('Only scenario/state-owned containers may be created; native Agent stores are read-only references.')
param create_containers bool = false
@description('Container-scoped grants. Built-in role GUIDs are policy identifiers, not deployment IDs.')
param bindings {
  container_name: string
  principal_id: string
  principal_type: 'User' | 'ServicePrincipal'
  role_id: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' | '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1' | 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
}[]

resource account 'Microsoft.Storage/storageAccounts@2025-06-01' existing = { name: account_name }
resource blob 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' existing = { parent: account, name: 'default' }
var binding_names = [for binding in bindings: binding.container_name]
var container_names = union(binding_names, [])
resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = [for name in container_names: if (create_containers) {
  parent: blob
  name: name
  properties: { publicAccess: 'None' }
}]
resource scopes 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' existing = [for name in container_names: {
  parent: blob
  name: name
}]
resource roles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for binding in bindings: {
  name: guid(account.id, binding.container_name, binding.principal_id, binding.role_id)
  scope: scopes[indexOf(container_names, binding.container_name)]
  properties: {
    principalId: binding.principal_id
    principalType: binding.principal_type
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', binding.role_id)
  }
  dependsOn: [containers]
}]
