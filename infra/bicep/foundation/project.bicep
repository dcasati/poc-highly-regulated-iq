import { us_region, approval } from '../types.bicep'
@description('Generic branding matching the foundation.')
param project_name string
@description('Explicit approved supported Azure region permitted by deployment validation rules.')
param location us_region
@description('Existing foundation account name.')
param account_name string
@description('Verified private DNS/TLS/keyless access and caller-role propagation.')
param private_connectivity approval
@description('Deployment caller GUID.')
param caller_principal_id string
@description('Deployment caller type.')
@allowed(['User', 'ServicePrincipal'])
param caller_principal_type string
resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = { name: account_name }
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: account
  name: '${project_name}-review'
  location: location
  identity: { type: 'SystemAssigned' }
  tags: { project: project_name, verification: private_connectivity.evidence_reference }
  properties: { displayName: '${project_name} document review', description: 'Private synthetic review; no production or FIPS readiness claim.' }
}
resource caller 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(project.id, caller_principal_id, '53ca6127-db72-4b80-b1b0-d745d6d5456d')
  scope: project
  properties: { principalId: caller_principal_id, principalType: caller_principal_type, roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '53ca6127-db72-4b80-b1b0-d745d6d5456d') }
}
output project_id string = project.id
output project_principal_id string = project.identity.principalId
output project_name string = project.name
output project_endpoint string = project.properties.endpoints['AI Foundry API']
