using '../foundation/runtime-bindings.bicep'
param foundry = { account: 'ai-review-demo-example', project: 'review-demo-review' }
param stores = { blob: 'stexampleagent', cosmos: 'cosmos-review-demo-example', search: 'srch-review-demo-example' }
param discovered = {
  files_container: 'replace-with-discovered-files-container'
  intermediate_container: 'replace-with-discovered-intermediate-container'
  database_name: 'replace-with-discovered-database'
}
param runtime_bindings = { approved: true, evidence_reference: 'EXAMPLE-NOT-CAPABILITY-STORE-OR-IDENTITY-VERIFICATION' }
