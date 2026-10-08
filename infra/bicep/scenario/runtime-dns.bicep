@description('Actual internal Container Apps environment defaultDomain.')
param domain string
@description('Actual environment static private IP.')
param private_ip string
@description('Verified existing PoC VNet ARM ID.')
param vnet_id string
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
  properties: { ttl: 300, aRecords: [{ ipv4Address: private_ip }] }
}
