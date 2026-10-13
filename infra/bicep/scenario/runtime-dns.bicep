@description('Actual internal Container Apps environment defaultDomain.')
param domain string
@description('Actual PE-owned NIC ARM ID in this resource group; supplied only after endpoint creation.')
param network_interface_id string
@description('Verified existing PoC VNet ARM ID.')
param vnet_id string
resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' existing = {
  name: last(split(network_interface_id, '/'))
}
resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' = { name: domain, location: 'global' }
resource link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: zone
  name: 'runtime'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: vnet_id } }
}
resource record 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: zone
  name: '*'
  properties: { ttl: 300, aRecords: [{ ipv4Address: nic.properties.ipConfigurations[0].properties.privateIPAddress }] }
}
