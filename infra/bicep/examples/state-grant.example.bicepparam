using '../state-backend/grant.bicep'
param storage_account_name = 'stexamplestate'
param deployment_principal_id = '11111111-1111-4111-8111-111111111111'
param deployment_principal_type = 'User'
param state_access = { approved: true, evidence_reference: 'EXAMPLE-NOT-STATE-ACCESS-APPROVAL' }
