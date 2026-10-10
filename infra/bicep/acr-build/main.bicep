import { us_region, reference, approval } from '../types.bicep'
@description('Generic PoC branding.')
param project_name string
@description('Same approved supported region as the existing registry/build VNet.')
param location us_region
@description('Existing private Premium registry in this resource group. This file never changes registry/network ownership or settings.')
param registry_name string
@description('Existing dedicated approved VNet-connected pool subnet.')
param build_subnet { vnet: reference, name: string }
@description('Separate preview/pool dependency approval, verified private registry endpoint and approved exact egress.')
param build_dependencies approval
@description('Supported dedicated ACR pool tier.')
@allowed(['S1', 'S2', 'S3'])
param tier string = 'S1'
@description('Dedicated pool instances.')
@minValue(1)
param instance_count int = 1
resource registry 'Microsoft.ContainerRegistry/registries@2025-04-01' existing = { name: registry_name }
resource pool 'Microsoft.ContainerRegistry/registries/agentPools@2025-03-01-preview' = {
  parent: registry
  name: '${replace(project_name, '-', '')}pool'
  location: location
  tags: { project: project_name, verification: build_dependencies.evidence_reference }
  properties: { count: instance_count, tier: tier, os: 'Linux', virtualNetworkSubnetResourceId: resourceId(build_subnet.vnet.resource_group_name, 'Microsoft.Network/virtualNetworks/subnets', build_subnet.vnet.name, build_subnet.name) }
}
output agent_pool_name string = pool.name
