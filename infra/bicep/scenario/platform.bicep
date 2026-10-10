import { us_region, reference, approval } from '../types.bicep'
@description('Generic PoC branding.')
@minLength(3)
@maxLength(16)
param project_name string
@description('Explicit approved supported Azure region permitted by deployment validation rules.')
param location us_region
@description('Existing verified private application Storage, Search and Foundry references. Account and project share a resource group.')
param existing { storage: reference, search: reference, foundry: reference, project_name: string }
@description('Backend-owned endpoint subnet ARM ID and foundation-owned registry DNS zone ARM ID.')
param network { endpoint_subnet_id: string, registry_dns_zone_id: string }
@description('Verified private/keyless prerequisites, Search S1+, system identity, scoped ownership and approved processing boundaries.')
param prerequisites approval

var suffix = take(uniqueString(subscription().id, project_name, 'scenario'), 8)
var prefix = '${project_name}-${suffix}'
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-${prefix}'
  location: location
  tags: { project: project_name, verification: prerequisites.evidence_reference }
}
resource registry 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: 'acr${replace(project_name, '-', '')}${suffix}'
  location: location
  sku: { name: 'Premium' }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Disabled'
    networkRuleBypassOptions: 'None'
    dataEndpointEnabled: true
    networkRuleSet: { defaultAction: 'Deny', ipRules: [] }
  }
}
resource search 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: existing.search.name
  scope: resourceGroup(existing.search.resource_group_name)
}
var containers = [for name in ['originals', 'review-state', 'approved', 'reviewed-evidence']: '${project_name}-${name}']
var app_bindings = map(containers, container => {
  container_name: container
  principal_id: identity.properties.principalId
  principal_type: 'ServicePrincipal'
  role_id: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
})
var search_bindings = map(['${project_name}-approved', '${project_name}-reviewed-evidence'], container => {
  container_name: container
  principal_id: search.identity.principalId
  principal_type: 'ServicePrincipal'
  role_id: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
})
module data '../modules/storage-bindings.bicep' = {
  name: 'application-containers'
  scope: resourceGroup(existing.storage.resource_group_name)
  params: { account_name: existing.storage.name, create_containers: true, bindings: concat(app_bindings, search_bindings) }
}
module pe '../modules/private-endpoint.bicep' = {
  name: 'registry-private-endpoint'
  params: { name: 'pe-${prefix}-registry', location: location, subnet_id: network.endpoint_subnet_id, target_id: registry.id, group_id: 'registry', dns_zone_ids: [network.registry_dns_zone_id] }
}
var grants = [
  { group: existing.search.resource_group_name, kind: 'search', name: existing.search.name, role: '1407120a-92aa-4202-b7e9-c0e197c71c8f' }
  { group: existing.foundry.resource_group_name, kind: 'foundry', name: existing.foundry.name, role: 'a97b65f3-24c7-4388-baec-2e87135dc908' }
  { group: resourceGroup().name, kind: 'registry', name: registry.name, role: '7f951dda-4ed3-4680-a7ca-43fe172d538d' }
]
module roles '../modules/service-roles.bicep' = [for (grant, i) in grants: {
  name: 'application-role-${i}'
  scope: resourceGroup(grant.group)
  params: { kind: grant.kind, name: grant.name, principal_id: identity.properties.principalId, role_id: grant.role }
}]
module project_role '../modules/project-role.bicep' = {
  name: 'application-project-role'
  scope: resourceGroup(existing.foundry.resource_group_name)
  params: { account_name: existing.foundry.name, project_name: existing.project_name, principal_id: identity.properties.principalId }
}
output identity_name string = identity.name
output identity_client_id string = identity.properties.clientId
output identity_id string = identity.id
output identity_principal_id string = identity.properties.principalId
output registry_name string = registry.name
output registry_login_server string = registry.properties.loginServer
output containers array = containers
