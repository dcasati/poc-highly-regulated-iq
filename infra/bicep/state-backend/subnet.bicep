@description('Existing PoC connectivity VNet.')
param vnet_name string
@description('Generic PoC branding.')
param project_name string
@description('Verified canonical PoC address space.')
param vnet_cidr string
resource network 'Microsoft.Network/virtualNetworks@2024-05-01' existing = { name: vnet_name }
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: network
  name: 'snet-${project_name}-private-endpoints'
  properties: { addressPrefix: cidrSubnet(vnet_cidr, 24, 2), defaultOutboundAccess: false, privateEndpointNetworkPolicies: 'Disabled' }
}
output id string = subnet.id
