using '../scenario/hosting.bicep'
param project_name = 'review-demo'
param location = 'eastus2'
param network = {
  runtime_subnet_id: '/subscriptions/22222222-2222-4222-8222-222222222222/resourceGroups/rg-review-demo-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-review-demo/subnets/snet-review-demo-runtime'
  endpoint_subnet_id: '/subscriptions/22222222-2222-4222-8222-222222222222/resourceGroups/rg-review-demo-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-review-demo/subnets/snet-review-demo-endpoints'
  vnet: { resource_group_name: 'rg-review-demo-connectivity', name: 'vnet-review-demo' }
}
param platform = { registry_name: 'acrexamplereview', identity_name: 'id-review-demo-example' }
param hosting_dependencies = { approved: true, evidence_reference: 'EXAMPLE-NOT-EGRESS-APPROVAL' }
