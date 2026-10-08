using '../scenario/platform.bicep'
param project_name = 'review-demo'
param location = 'eastus2'
param existing = {
  storage: { resource_group_name: 'rg-review-demo-foundation', name: 'stexampleapplication' }
  search: { resource_group_name: 'rg-review-demo-foundation', name: 'srch-review-demo-example' }
  foundry: { resource_group_name: 'rg-review-demo-foundation', name: 'ai-review-demo-example' }
  project_name: 'review-demo-review'
}
param network = {
  endpoint_subnet_id: '/subscriptions/22222222-2222-4222-8222-222222222222/resourceGroups/rg-review-demo-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-review-demo/subnets/snet-review-demo-private-endpoints'
  registry_dns_zone_id: '/subscriptions/22222222-2222-4222-8222-222222222222/resourceGroups/rg-review-demo-foundation/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io'
}
param prerequisites = { approved: true, evidence_reference: 'EXAMPLE-NOT-FOUNDATION-OR-PROCESSING-VERIFICATION' }
