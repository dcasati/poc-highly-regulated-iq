using '../connectivity/main.bicep'
param project_name = 'review-demo'
param location = 'eastus2'
param administration = { approved: true, evidence_reference: 'SYNTHETIC-ONLY-EXAMPLE-NOT-APPROVAL' }
param vnet_cidr = '10.80.0.0/16'
param ssh_public_key = 'REPLACE-WITH-APPROVED-SSH-PUBLIC-KEY-NOT-A-PRIVATE-KEY'
param image_version = 'REPLACE-WITH-APPROVED-EXPLICIT-VERSION'
param approved_egress = []
