using '../acr-build/main.bicep'
param project_name = 'review-demo'
param location = 'eastus2'
param registry_name = 'acrexamplereview'
param build_subnet = { vnet: { resource_group_name: 'rg-review-demo-connectivity', name: 'vnet-review-demo' }, name: 'snet-review-demo-build' }
param build_dependencies = { approved: true, evidence_reference: 'EXAMPLE-NOT-PREVIEW-OR-BUILD-EGRESS-APPROVAL' }
