import { us_region } from '../types.bicep'

@description('New endpoint name; only deploy within its chosen Bicep-owned resource boundary.')
param name string
@description('Explicit US region.')
param location us_region
@description('Verified PoC endpoint subnet ARM ID; subnet remains owned by the backend boundary.')
param subnet_id string
@description('Verified target ARM ID.')
param target_id string
@description('Documented private-link group, not a guessed subresource.')
param group_id string
@description('Verified private DNS zone ARM IDs. Cross-RG zone rights are required.')
param dns_zone_ids string[]

resource endpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: name
  location: location
  properties: {
    subnet: { id: subnet_id }
    privateLinkServiceConnections: [{
      name: name
      properties: {
        privateLinkServiceId: target_id
        groupIds: [group_id]
        requestMessage: 'PoC boundary only; target owner must review and approve.'
      }
    }]
  }
}
resource zones 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: endpoint
  name: 'private'
  properties: {
    privateDnsZoneConfigs: [for (id, i) in dns_zone_ids: {
      name: 'zone-${i}'
      properties: { privateDnsZoneId: id }
    }]
  }
}
output id string = endpoint.id
