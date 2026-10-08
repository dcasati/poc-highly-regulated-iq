using '../foundation/project.bicep'
param project_name = 'review-demo'
param location = 'eastus2'
param account_name = 'ai-review-demo-example'
param private_connectivity = { approved: true, evidence_reference: 'EXAMPLE-NOT-PRIVATE-VERIFICATION' }
param caller_principal_id = '11111111-1111-4111-8111-111111111111'
param caller_principal_type = 'User'
