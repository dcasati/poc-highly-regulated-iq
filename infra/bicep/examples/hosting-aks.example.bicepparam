using '../scenario/hosting.bicep'
param project_name = 'review-demo'
param location = 'eastus2'
param hosting = {
  kind: 'aks'
  kubernetes_version: 'REPLACE-WITH-SUPPORTED-VERSION'
  os_sku: 'AzureLinux3'
  vm_size: 'Standard_D4_v5'
  mesh_revision: 'REPLACE-WITH-SUPPORTED-REVISION'
  node_count: 2
  pod_cidr: '10.244.0.0/16'
  service_cidr: '10.245.0.0/16'
  dns_service_ip: '10.245.0.10'
  deployer_principal_id: '11111111-1111-4111-8111-111111111111'
}
param network = {
  runtime_subnet_id: '/subscriptions/22222222-2222-4222-8222-222222222222/resourceGroups/rg-review-demo-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-review-demo/subnets/snet-review-demo-runtime'
  vnet: { resource_group_name: 'rg-review-demo-connectivity', name: 'vnet-review-demo' }
}
param platform = { registry_name: 'acrexamplereview', identity_name: 'id-review-demo-example' }
param hosting_dependencies = { approved: true, evidence_reference: 'EXAMPLE-NOT-AKS-COMPATIBILITY-OR-EGRESS-APPROVAL' }
