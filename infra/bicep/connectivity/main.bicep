import { us_region, approval } from '../types.bicep'

@description('Generic PoC branding matching the precreated connectivity resource group.')
@minLength(3)
@maxLength(16)
param project_name string
@description('Explicit approved US region.')
param location us_region
@description('Separately approved synthetic-only administration and reviewed destination-specific egress; not regulated transport approval.')
param administration approval
@description('Canonical new PoC 10.x.0.0/16 address space.')
param vnet_cidr string
@description('SSH public key only. No password, private key or tailnet auth key.')
param ssh_public_key string
@description('Private administration username.')
param admin_username string = 'pocadmin'
@description('Approved VM size.')
param vm_size string = 'Standard_B2s'
@description('Explicit reviewed Ubuntu 24.04 image version; do not use latest.')
@minLength(1)
param image_version string
@description('Exact reviewed IP/CIDR destinations for bootstrap, package access and tailnet control/relay. No Internet/AzureCloud wildcard rule.')
@maxLength(100)
param approved_egress {
  @minLength(1)
  destination_cidr: string
  @minValue(1)
  @maxValue(65535)
  port: int
}[]

var name = '${project_name}-connectivity'
var egress_rules = [for (rule, i) in approved_egress: {
  name: 'approved-${i}'
  properties: {
    priority: 100 + i
    direction: 'Outbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: string(rule.port)
    sourceAddressPrefix: '*'
    destinationAddressPrefix: rule.destination_cidr
    description: administration.evidence_reference
  }
}]
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${name}'
  location: location
  properties: {
    securityRules: concat(egress_rules, [
      {
        name: 'azure-dns'
        properties: { priority: 3000, direction: 'Outbound', access: 'Allow', protocol: '*', sourcePortRange: '*', destinationPortRange: '53', sourceAddressPrefix: '*', destinationAddressPrefix: '168.63.129.16/32' }
      }
      {
        name: 'private-https'
        properties: { priority: 3010, direction: 'Outbound', access: 'Allow', protocol: 'Tcp', sourcePortRange: '*', destinationPortRange: '443', sourceAddressPrefix: '*', destinationAddressPrefix: cidrSubnet(vnet_cidr, 24, 2) }
      }
      {
        name: 'deny-other-egress'
        properties: { priority: 4096, direction: 'Outbound', access: 'Deny', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: '*', destinationAddressPrefix: '*' }
      }
      {
        name: 'deny-unsolicited-inbound'
        properties: { priority: 4096, direction: 'Inbound', access: 'Deny', protocol: '*', sourcePortRange: '*', destinationPortRange: '*', sourceAddressPrefix: '*', destinationAddressPrefix: '*' }
      }
    ])
  }
}
resource ip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-${name}-egress'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}
resource nat 'Microsoft.Network/natGateways@2024-05-01' = {
  name: 'nat-${name}'
  location: location
  sku: { name: 'Standard' }
  properties: { idleTimeoutInMinutes: 10, publicIpAddresses: [{ id: ip.id }] }
}
resource network 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${project_name}'
  location: location
  tags: { project: project_name, managed_by: 'Bicep' }
  properties: { addressSpace: { addressPrefixes: [vnet_cidr] } }
}
resource router 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: network
  name: 'snet-${name}'
  properties: {
    addressPrefix: cidrSubnet(vnet_cidr, 27, 24)
    defaultOutboundAccess: false
    networkSecurityGroup: { id: nsg.id }
    natGateway: { id: nat.id }
  }
}
resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${name}'
  location: location
  properties: {
    enableIPForwarding: true
    ipConfigurations: [{ name: 'private', properties: { subnet: { id: router.id }, privateIPAllocationMethod: 'Dynamic' } }]
  }
}
resource vm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: name
  location: location
  properties: {
    hardwareProfile: { vmSize: vm_size }
    securityProfile: { securityType: 'TrustedLaunch', uefiSettings: { secureBootEnabled: true, vTpmEnabled: true } }
    storageProfile: {
      imageReference: { publisher: 'Canonical', offer: 'ubuntu-24_04-lts', sku: 'server', version: image_version }
      osDisk: { name: 'os-${name}', createOption: 'FromImage', caching: 'ReadWrite', diskSizeGB: 32, managedDisk: { storageAccountType: 'StandardSSD_LRS' } }
    }
    osProfile: {
      computerName: name
      adminUsername: admin_username
      customData: base64(loadTextContent('../../connectivity/cloud-init.yaml'))
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        ssh: { publicKeys: [{ path: '/home/${admin_username}/.ssh/authorized_keys', keyData: ssh_public_key }] }
      }
    }
    networkProfile: { networkInterfaces: [{ id: nic.id }] }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}
output network_id string = network.id
output vm_id string = vm.id
