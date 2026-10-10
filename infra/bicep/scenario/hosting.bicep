import { us_region, approval, reference } from '../types.bicep'
@description('Generic PoC branding.')
param project_name string
@description('Explicit approved supported Azure region permitted by deployment validation rules.')
param location us_region
@description('Dedicated delegated Container Apps runtime subnet, separate endpoint subnet/VNet and reviewed controlled dependency egress.')
param network { runtime_subnet_id: string, endpoint_subnet_id: string, vnet: reference }
@description('Separate hosting approval after exact platform dependencies and egress review, not runtime cryptographic acceptance.')
param hosting_dependencies approval
var prefix = '${project_name}-${take(uniqueString(subscription().id, project_name, 'scenario'), 8)}'
resource environment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: 'cae-${prefix}'
  location: location
  tags: { project: project_name, verification: hosting_dependencies.evidence_reference }
  properties: {
    publicNetworkAccess: 'Disabled'
    peerTrafficConfiguration: { encryption: { enabled: true } }
    vnetConfiguration: { internal: true, infrastructureSubnetId: network.runtime_subnet_id }
    workloadProfiles: [{ name: 'Consumption', workloadProfileType: 'Consumption' }]
  }
}
resource private_link_zone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.${location}.azurecontainerapps.io'
  location: 'global'
}
resource private_link_vnet 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: private_link_zone
  name: 'runtime'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: resourceId(network.vnet.resource_group_name, 'Microsoft.Network/virtualNetworks', network.vnet.name) } }
}
module endpoint '../modules/private-endpoint.bicep' = {
  name: 'container-apps-private-endpoint'
  params: {
    name: 'pe-${prefix}-container-apps'
    location: location
    subnet_id: network.endpoint_subnet_id
    target_id: environment.id
    group_id: 'managedEnvironments'
    dns_zone_ids: [private_link_zone.id]
  }
}
module dns './runtime-dns.bicep' = {
  name: 'container-apps-private-dns'
  params: { domain: environment.properties.defaultDomain, network_interface_id: endpoint.outputs.network_interface_id, vnet_id: resourceId(network.vnet.resource_group_name, 'Microsoft.Network/virtualNetworks', network.vnet.name) }
}
output container_apps_environment_name string = environment.name
@description('Actual environment domain for separately approved SPA redirect preparation, not a deployed portal URL.')
output container_apps_default_domain string = environment.properties.defaultDomain
