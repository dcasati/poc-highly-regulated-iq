import { us_region, approval, reference } from '../types.bicep'
@description('Generic PoC branding.')
@minLength(3)
@maxLength(16)
param project_name string
@description('Explicit approved US region.')
param location us_region
@description('Separate approval for a new backend only. Scoped access grants and each state migration need separate approval.')
param bootstrap approval
@description('Verified PoC-owned connectivity VNet, not another project.')
param network reference
@description('Verified canonical PoC 10.x.0.0/16.')
param vnet_cidr string
@description('Dedicated private state container.')
param container_name string = 'tfstate'

var account_name = 'st${take(replace(project_name, '-', ''), 9)}${uniqueString(subscription().id, project_name, 'state')}'
module storage '../modules/storage.bicep' = {
  name: 'state-storage'
  params: { name: account_name, location: location }
}
module endpoint_subnet './subnet.bicep' = {
  name: 'state-endpoint-subnet'
  scope: resourceGroup(network.resource_group_name)
  params: { vnet_name: network.name, project_name: project_name, vnet_cidr: vnet_cidr }
}
resource blob_dns 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  tags: { project: project_name, managed_by: 'Bicep', approval: bootstrap.evidence_reference }
}
resource link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: blob_dns
  name: 'link-${project_name}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: resourceId(network.resource_group_name, 'Microsoft.Network/virtualNetworks', network.name) }
  }
}
module pe '../modules/private-endpoint.bicep' = {
  name: 'state-private-endpoint'
  params: {
    name: 'pe-${project_name}-state-blob'
    location: location
    subnet_id: endpoint_subnet.outputs.id
    target_id: storage.outputs.id
    group_id: 'blob'
    dns_zone_ids: [blob_dns.id]
  }
}
module container '../modules/containers.bicep' = {
  name: 'state-container'
  params: {
    account_name: storage.outputs.name
    container_names: [container_name]
  }
}
output storage_account_name string = storage.outputs.name
output endpoint_subnet_id string = endpoint_subnet.outputs.id
output blob_dns_id string = blob_dns.id
