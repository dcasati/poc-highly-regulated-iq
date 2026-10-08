using '../state-backend/main.bicep'
param project_name = 'review-demo'
param location = 'eastus2'
param bootstrap = { approved: true, evidence_reference: 'EXAMPLE-NOT-BACKEND-APPROVAL' }
param network = { resource_group_name: 'rg-review-demo-connectivity', name: 'vnet-review-demo' }
param vnet_cidr = '10.80.0.0/16'
