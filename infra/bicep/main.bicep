targetScope = 'subscription'
import { us_region, approval, model, egress_rule } from './types.bicep'
@description('New Bicep-owned solution branding; never deploy over the current separately owned solution.')
@minLength(3)
@maxLength(16)
param project_name string
@description('Explicit approved supported Azure region permitted by deployment validation rules. Verify model/CU availability before authorizing deployment.')
param location us_region
@description('Canonical nonoverlapping new PoC address space.')
param vnet_cidr string
@description('Separate synthetic-only administration/network approval.')
param administration approval
@description('SSH public key, never private key or tailnet enrollment credential.')
param ssh_public_key string
@description('Pinned approved Ubuntu 24.04 VM image version.')
param image_version string
@description('Exact reviewed administration package/tailnet destinations. Empty compiler fixture is not operational.')
param administration_egress egress_rule[]
@description('Exact reviewed ACA and build dependency destinations. NAT provides transport, not permission.')
param platform_destinations { runtime: egress_rule[], build: egress_rule[], verification: approval }
@description('Pinned supported model versions, SKU and per-model quota permitted by deployment validation rules.')
param models { chat: model, embedding: model }
@description('Verified deployment caller object GUID; subsequent directory/service actions remain separate.')
param caller_principal_id string
@allowed(['User', 'ServicePrincipal'])
@description('Actual caller principal type.')
param caller_principal_type string

var boundaries = ['connectivity', 'foundation', 'scenario']
resource groups 'Microsoft.Resources/resourceGroups@2024-03-01' = [for boundary in boundaries: {
  name: 'rg-${project_name}-${boundary}'
  location: location
  tags: { project: project_name, managed_by: 'Bicep', purpose: boundary }
}]
module connectivity './connectivity/main.bicep' = {
  name: 'review-connectivity'
  scope: groups[0]
  params: {
    project_name: project_name
    location: location
    administration: administration
    vnet_cidr: vnet_cidr
    ssh_public_key: ssh_public_key
    image_version: image_version
    approved_egress: administration_egress
  }
}
module private_network './foundation/private-network.bicep' = {
  name: 'review-private-network'
  scope: groups[1]
  params: {
    project_name: project_name
    location: location
    network: { resource_group_name: groups[0].name, name: connectivity.outputs.network_name }
    vnet_cidr: vnet_cidr
  }
}
module foundation './foundation/main.bicep' = {
  name: 'review-foundation'
  scope: groups[1]
  params: {
    project_name: project_name
    location: location
    network: { resource_group_name: groups[0].name, name: connectivity.outputs.network_name }
    vnet_cidr: vnet_cidr
    endpoint_subnet_name: private_network.outputs.endpoint_subnet_name
    blob_dns_resource_group: groups[1].name
    hosting: 'container_apps'
    models: models
    caller_principal_id: caller_principal_id
    caller_principal_type: caller_principal_type
    outbound: {
      nat_gateway_id: connectivity.outputs.nat_gateway_id
      runtime: platform_destinations.runtime
      build: platform_destinations.build
      verification: platform_destinations.verification
    }
  }
}
output resource_groups object = { connectivity: groups[0].name, foundation: groups[1].name, scenario: groups[2].name }
output network object = {
  vnet: { resource_group_name: groups[0].name, name: connectivity.outputs.network_name }
  endpoint_subnet_id: private_network.outputs.endpoint_subnet_id
  registry_dns_zone_id: foundation.outputs.registry_dns_zone_id
  reserved_subnets: foundation.outputs.reserved_subnets
}
output services object = {
  account_name: foundation.outputs.account_name
  account_id: foundation.outputs.account_id
  search_name: foundation.outputs.search_name
  application_storage_name: foundation.outputs.application_storage_name
  agent_storage_name: foundation.outputs.agent_storage_name
  agent_cosmos_name: foundation.outputs.agent_cosmos_name
  endpoints: foundation.outputs.service_endpoints
  models: foundation.outputs.model_deployments
  chat_rai_policy_id: foundation.outputs.chat_rai_policy_id
}
