@description('Verified existing Foundry account name.')
param account_name string
@description('Verified existing child project name.')
param project_name string
@description('Verified application or caller principal GUID.')
param principal_id string
@description('Managed application or deployment caller type.')
@allowed(['User', 'ServicePrincipal'])
param principal_type string = 'ServicePrincipal'
resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = { name: account_name }
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = { parent: account, name: project_name }
resource role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(project.id, principal_id, '53ca6127-db72-4b80-b1b0-d745d6d5456d')
  scope: project
  properties: {
    principalId: principal_id
    principalType: principal_type
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '53ca6127-db72-4b80-b1b0-d745d6d5456d')
  }
}
