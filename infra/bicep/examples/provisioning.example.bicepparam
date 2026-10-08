using '../foundation/provisioning.bicep'
param account_name = 'ai-review-demo-example'
param project_child_name = 'review-demo-review'
param stores = { blob: 'stexampleagent', cosmos: 'cosmos-review-demo-example', search: 'srch-review-demo-example' }
param endpoints = {
  blob: 'https://stexampleagent.blob.core.windows.net/'
  cosmos: 'https://cosmos-review-demo-example.documents.azure.com:443/'
  search: 'https://srch-review-demo-example.search.windows.net'
}
param provisioning = { approved: true, evidence_reference: 'EXAMPLE-NOT-IDENTITY-OR-ROLE-VERIFICATION' }
