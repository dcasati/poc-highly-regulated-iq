import { us_region, approval, reference } from '../types.bicep'
import { hosting_config } from './hosting-types.bicep'
@description('Generic PoC branding.')
param project_name string
@description('Explicit US region.')
param location us_region
@description('First-choice Container Apps OR approved private AKS fallback; never both.')
param hosting hosting_config = { kind: 'container_apps' }
@description('Dedicated approved runtime subnet, existing VNet and reviewed UDR/firewall dependency egress. AKS subnet must be undelegated.')
param network { runtime_subnet_id: string, vnet: reference }
@description('Verified private scenario registry and application identity names in this resource group.')
param platform { registry_name: string, identity_name: string }
@description('Separate hosting approval after exact platform dependencies and egress review, not runtime cryptographic acceptance.')
param hosting_dependencies approval
var prefix = '${project_name}-${take(uniqueString(subscription().id, project_name, 'scenario'), 8)}'
resource environment 'Microsoft.App/managedEnvironments@2025-07-01' = if (hosting.kind == 'container_apps') {
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
module dns './runtime-dns.bicep' = if (hosting.kind == 'container_apps') {
  name: 'container-apps-private-dns'
  params: { domain: environment!.properties.defaultDomain, private_ip: environment!.properties.staticIp, vnet_id: resourceId(network.vnet.resource_group_name, 'Microsoft.Network/virtualNetworks', network.vnet.name) }
}
module aks './hosting-aks.bicep' = if (hosting.kind == 'aks') {
  name: 'private-aks-hosting'
  params: { project_name: project_name, location: location, config: hosting, network: network, platform: platform, verification: hosting_dependencies.evidence_reference }
}
output container_apps_environment_name string? = hosting.kind == 'container_apps' ? environment!.name : null
output aks_cluster_name string? = hosting.kind == 'aks' ? aks!.outputs.cluster_name : null
