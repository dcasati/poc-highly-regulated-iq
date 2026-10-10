import { us_region, platform_egress } from '../types.bicep'
@description('Generic branding.')
param project_name string
@description('Explicit approved supported Azure region permitted by deployment validation rules.')
param location us_region
@description('Existing PoC VNet name.')
param vnet_name string
@description('Verified canonical PoC address space.')
param vnet_cidr string
@description('Reserved PoC-owned private endpoint subnet CIDR.')
param endpoint_cidr string
@description('Approved controlled outbound transport for runtime/build only; no unrestricted Internet rule.')
param outbound platform_egress
var subnets = [
  { name: 'runtime', number: 1, delegated: true }
  { name: 'build', number: 4, delegated: false }
]
resource network 'Microsoft.Network/virtualNetworks@2024-05-01' existing = { name: vnet_name }
resource nsgs 'Microsoft.Network/networkSecurityGroups@2024-05-01' = [for subnet in subnets: {
  name: 'nsg-${project_name}-${subnet.name}'
  location: location
  properties: {
    securityRules: concat([
      {
        name: 'private-endpoint-https'
        properties: { priority: 100, direction: 'Outbound', access: 'Allow', protocol: 'Tcp', sourcePortRange: '*', destinationPortRange: '443', sourceAddressPrefix: '*', destinationAddressPrefix: endpoint_cidr }
      }
      {
        name: 'azure-dns'
        properties: { priority: 110, direction: 'Outbound', access: 'Allow', protocol: '*', sourcePortRange: '*', destinationPortRange: '53', sourceAddressPrefix: '*', destinationAddressPrefix: '168.63.129.16/32' }
      }
      {
        name: 'entra-https'
        properties: { priority: 120, direction: 'Outbound', access: 'Allow', protocol: 'Tcp', sourcePortRange: '*', destinationPortRange: '443', sourceAddressPrefix: '*', destinationAddressPrefix: 'AzureActiveDirectory' }
      }
      {
        name: 'subnet-internal'
        properties: { priority: 130, direction: 'Outbound', access: 'Allow', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: '*', destinationAddressPrefix: cidrSubnet(vnet_cidr, 24, subnet.number) }
      }
      {
        name: 'deny-other-egress'
        properties: { priority: 4096, direction: 'Outbound', access: 'Deny', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: '*', destinationAddressPrefix: '*' }
      }
    ], map((subnet.name == 'runtime' ? outbound.runtime : outbound.build), (rule, i) => {
      name: 'approved-platform-${i}'
      properties: {
        priority: 200 + i
        direction: 'Outbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourcePortRange: '*'
        destinationPortRange: string(rule.port)
        sourceAddressPrefix: '*'
        destinationAddressPrefix: rule.destination_cidr
        description: outbound.verification.evidence_reference
      }
    }))
  }
}]
resource reservations 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = [for (subnet, i) in subnets: {
  parent: network
  name: 'snet-${project_name}-${subnet.name}'
  properties: {
    addressPrefix: cidrSubnet(vnet_cidr, 24, subnet.number)
    defaultOutboundAccess: false
    networkSecurityGroup: { id: nsgs[i].id }
    natGateway: { id: outbound.nat_gateway_id }
    delegations: subnet.delegated ? [{
      name: 'container-apps'
      properties: { serviceName: 'Microsoft.App/environments' }
    }] : []
  }
}]
output runtime_subnet_id string = reservations[0].id
output build_subnet_id string = reservations[1].id
