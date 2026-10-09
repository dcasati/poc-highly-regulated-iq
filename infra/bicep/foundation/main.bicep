import { us_region, reference, model, platform_egress } from '../types.bicep'
@description('Generic PoC branding.')
@minLength(3)
@maxLength(16)
param project_name string
@description('Explicit supported US region; verify US Data Zone inference and both CU processing boundaries.')
param location us_region
@description('Verified PoC connectivity VNet.')
param network reference
@description('Verified single canonical PoC address space.')
param vnet_cidr string
@description('Backend-owned private endpoint subnet name.')
param endpoint_subnet_name string
@description('Backend-owned Blob DNS resource group.')
param blob_dns_resource_group string
@description('Choose runtime reservation before provisioning; runtime itself remains deferred.')
@allowed(['container_apps', 'aks'])
param hosting string = 'container_apps'
@description('Supported approved models with explicit versions/SKUs/model-specific quota; Global SKUs are not allowed.')
param models { chat: model, embedding: model }
@description('Verified deployment caller GUID for scoped bootstrap/operator grants.')
param caller_principal_id string
@description('Verified deployment caller principal type.')
@allowed(['User', 'ServicePrincipal'])
param caller_principal_type string
@description('Bicep-owned or intentionally existing outbound-only NAT and separately reviewed exact runtime/build destinations. Agent subnet receives no NAT.')
param outbound platform_egress

var suffix = uniqueString(subscription().id, project_name, 'foundation')
var prefix = '${project_name}-${take(suffix, 6)}'
var storage_names = [for purpose in ['app', 'agt']: 'st${take(replace(project_name, '-', ''), 5)}${purpose}${suffix}']
module reservations './network.bicep' = {
  name: 'foundation-subnet-reservations'
  scope: resourceGroup(network.resource_group_name)
  params: {
    project_name: project_name
    location: location
    vnet_name: network.name
    vnet_cidr: vnet_cidr
    endpoint_cidr: cidrSubnet(vnet_cidr, 24, 2)
    hosting: hosting
    outbound: outbound
  }
}
module stores '../modules/storage.bicep' = [for (name, i) in storage_names: {
  name: 'foundation-storage-${i}'
  params: { name: name, location: location }
}]
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2025-04-15' = {
  name: 'cosmos-${prefix}'
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
    networkAclBypass: 'None'
    minimalTlsVersion: 'Tls12'
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    capabilities: [{ name: 'EnableServerless' }]
    locations: [{ locationName: location, failoverPriority: 0, isZoneRedundant: false }]
  }
}
resource search 'Microsoft.Search/searchServices@2025-05-01' = {
  name: 'srch-${prefix}'
  location: location
  sku: { name: 'standard' }
  identity: { type: 'SystemAssigned' }
  properties: {
    replicaCount: 1
    partitionCount: 1
    publicNetworkAccess: 'disabled'
    disableLocalAuth: true
    networkRuleSet: { bypass: 'None', ipRules: [] }
    semanticSearch: 'standard'
  }
}
var dns_names = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.search.windows.net'
  'privatelink.documents.azure.com'
  'privatelink.azurecr.io'
]
resource dns 'Microsoft.Network/privateDnsZones@2024-06-01' = [for name in dns_names: {
  name: name
  location: 'global'
  tags: { project: project_name, managed_by: 'Bicep' }
}]
resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (name, i) in dns_names: {
  parent: dns[i]
  name: 'link-${project_name}'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: resourceId(network.resource_group_name, 'Microsoft.Network/virtualNetworks', network.name) } }
}]
module caller_blob '../modules/service-roles.bicep' = {
  name: 'caller-agent-blob'
  params: { kind: 'storage', name: stores[1].outputs.name, principal_id: caller_principal_id, principal_type: caller_principal_type, role_id: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' }
}
module caller_cosmos '../modules/service-roles.bicep' = {
  name: 'caller-agent-cosmos'
  params: { kind: 'cosmos', name: cosmos.name, principal_id: caller_principal_id, principal_type: caller_principal_type, role_id: '230815da-be43-4aae-9cb4-875f7bd000aa' }
}
resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: 'ai-${prefix}'
  location: location
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    allowProjectManagement: true
    customSubDomainName: 'ai-${prefix}'
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
    restrictOutboundNetworkAccess: true
    networkAcls: { defaultAction: 'Deny', bypass: 'None', ipRules: [], virtualNetworkRules: [] }
    networkInjections: [{ scenario: 'agent', subnetArmId: reservations.outputs.agent_subnet_id, useMicrosoftManagedNetwork: false }]
  }
  dependsOn: [caller_blob, caller_cosmos, links]
}
var harm_filter_pairs = [
  { name: 'Hate', source: 'Prompt' }
  { name: 'Hate', source: 'Completion' }
  { name: 'Sexual', source: 'Prompt' }
  { name: 'Sexual', source: 'Completion' }
  { name: 'Violence', source: 'Prompt' }
  { name: 'Violence', source: 'Completion' }
  { name: 'Selfharm', source: 'Prompt' }
  { name: 'Selfharm', source: 'Completion' }
]
var harm_filters = [for filter in harm_filter_pairs: {
  name: filter.name
  source: filter.source
  enabled: true
  blocking: true
  severityThreshold: 'Medium'
}]
var prompt_shields = [for detector in ['Jailbreak', 'Indirect Attack']: {
  name: detector
  source: 'Prompt'
  enabled: true
  blocking: true
}]
var protected_material = [for detector in ['Protected Material Text', 'Protected Material Code']: {
  name: detector
  source: 'Completion'
  enabled: true
  blocking: true
}]
resource chat_prompt_shields 'Microsoft.CognitiveServices/accounts/raiPolicies@2025-06-01' = {
  parent: account
  name: 'chat-prompt-shields'
  properties: {
    basePolicyName: 'Microsoft.Default'
    mode: 'Blocking'
    contentFilters: concat(harm_filters, prompt_shields, protected_material)
  }
}
// Document protection also requires the documented Chat Completions document delimiters;
// policy attachment alone does not establish indirect-attack coverage for Responses.
var model_list = [{ deployment: 'chat', config: models.chat }, { deployment: 'embedding', config: models.embedding }]
resource deployments 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = [for item in model_list: {
  parent: account
  name: item.deployment
  sku: { name: item.config.sku, capacity: item.config.capacity }
  properties: union(
    { model: { format: 'OpenAI', name: item.config.name, version: item.config.version }, versionUpgradeOption: 'NoAutoUpgrade' },
    item.deployment == 'chat' ? { raiPolicyName: chat_prompt_shields.name } : {}
  )
}]
var endpoint_subnet_id = resourceId(network.resource_group_name, 'Microsoft.Network/virtualNetworks/subnets', network.name, endpoint_subnet_name)
var blob_dns_id = resourceId(blob_dns_resource_group, 'Microsoft.Network/privateDnsZones', 'privatelink.blob.${environment().suffixes.storage}')
var targets = [
  { name: 'foundry', id: account.id, group: 'account', zones: [dns[0].id, dns[1].id, dns[2].id] }
  { name: 'search', id: search.id, group: 'searchService', zones: [dns[3].id] }
  { name: 'application-blob', id: stores[0].outputs.id, group: 'blob', zones: [blob_dns_id] }
  { name: 'agent-blob', id: stores[1].outputs.id, group: 'blob', zones: [blob_dns_id] }
  { name: 'cosmos', id: cosmos.id, group: 'Sql', zones: [dns[4].id] }
]
module endpoints '../modules/private-endpoint.bicep' = [for i in range(0, 5): {
  name: 'endpoint-${i}'
  params: { name: 'pe-${prefix}-${targets[i].name}', location: location, subnet_id: endpoint_subnet_id, target_id: targets[i].id, group_id: targets[i].group, dns_zone_ids: targets[i].zones }
}]
resource blob_link 'Microsoft.Search/searchServices/sharedPrivateLinkResources@2025-05-01' = {
  parent: search
  name: '${project_name}-application-blob'
  properties: { groupId: 'blob', privateLinkResourceId: stores[0].outputs.id, requestMessage: 'Target-owner approval required for private human-reviewed application indexing.' }
}
var service_grants = [
  { kind: 'foundry', name: account.name, principal: account.identity.principalId, role: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd', type: 'ServicePrincipal' }
  { kind: 'foundry', name: account.name, principal: search.identity.principalId, role: 'a97b65f3-24c7-4388-baec-2e87135dc908', type: 'ServicePrincipal' }
  { kind: 'foundry', name: account.name, principal: caller_principal_id, role: 'a97b65f3-24c7-4388-baec-2e87135dc908', type: caller_principal_type }
  { kind: 'search', name: search.name, principal: caller_principal_id, role: '7ca78c08-252a-4471-8644-bb5ff32d4ba0', type: caller_principal_type }
  { kind: 'search', name: search.name, principal: caller_principal_id, role: '8ebe5a00-799e-43f5-93ac-243d3dce84a7', type: caller_principal_type }
]
module grants '../modules/service-roles.bicep' = [for i in range(0, 5): {
  name: 'foundation-role-${i}'
  params: { kind: service_grants[i].kind, name: service_grants[i].name, principal_id: service_grants[i].principal, role_id: service_grants[i].role, principal_type: service_grants[i].type }
}]
output account_name string = account.name
output search_name string = search.name
output application_storage_name string = stores[0].outputs.name
output agent_storage_name string = stores[1].outputs.name
output agent_cosmos_name string = cosmos.name
output model_deployments object = { chat: deployments[0].name, embedding: deployments[1].name }
output reserved_subnets object = { agent: reservations.outputs.agent_subnet_id, runtime: reservations.outputs.runtime_subnet_id, build: reservations.outputs.build_subnet_id }
output account_id string = account.id
output chat_rai_policy_id string = chat_prompt_shields.id
output service_endpoints object = {
  blob: stores[0].outputs.blob_endpoint
  agent_blob: stores[1].outputs.blob_endpoint
  cosmos: cosmos.properties.documentEndpoint
  search: 'https://${search.name}.search.windows.net/'
  content: 'https://${account.name}.cognitiveservices.azure.com/'
}
output registry_dns_zone_id string = dns[5].id
