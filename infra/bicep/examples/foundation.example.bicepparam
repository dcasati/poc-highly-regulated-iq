using '../foundation/main.bicep'
param project_name = 'review-demo'
param location = 'eastus2'
param network = { resource_group_name: 'rg-review-demo-connectivity', name: 'vnet-review-demo' }
param vnet_cidr = '10.80.0.0/16'
param endpoint_subnet_name = 'snet-review-demo-private-endpoints'
param blob_dns_resource_group = 'rg-review-demo-state'
param models = {
  chat: { name: 'gpt-5.2', version: '2025-12-11', sku: 'DataZoneStandard', capacity: 10 }
  embedding: { name: 'text-embedding-3-large', version: '1', sku: 'DataZoneStandard', capacity: 10 }
}
param caller_principal_id = '11111111-1111-4111-8111-111111111111'
param caller_principal_type = 'User'
param outbound = {
  nat_gateway_id: '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-review-demo-connectivity/providers/Microsoft.Network/natGateways/nat-review-demo-connectivity'
  runtime: []
  build: []
  verification: { approved: true, evidence_reference: 'EXAMPLE-reviewed-exact-destinations-required' }
}
