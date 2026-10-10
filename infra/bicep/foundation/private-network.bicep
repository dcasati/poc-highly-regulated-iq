import { us_region, reference } from '../types.bicep'
@description('Generic PoC branding.')
param project_name string
@description('Explicit approved supported Azure region permitted by deployment validation rules.')
param location us_region
@description('Connectivity created by Bicep, or an intentionally supplied owned existing VNet.')
param network reference
@description('Canonical reviewed 10.x.0.0/16 address space.')
param vnet_cidr string

module endpoint_subnet '../state-backend/subnet.bicep' = {
  name: 'private-endpoint-subnet'
  scope: resourceGroup(network.resource_group_name)
  params: { project_name: project_name, vnet_name: network.name, vnet_cidr: vnet_cidr }
}
resource blob_dns 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  tags: { project: project_name, managed_by: 'Bicep' }
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
output endpoint_subnet_id string = endpoint_subnet.outputs.id
output endpoint_subnet_name string = 'snet-${project_name}-private-endpoints'
output blob_dns_id string = blob_dns.id
output location string = location
