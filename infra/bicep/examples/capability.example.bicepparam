using '../foundation/capability.bicep'
param account_name = 'ai-review-demo-example'
param project_child_name = 'review-demo-review'
param connections = { blob: 'stexampleagent', cosmos: 'cosmos-review-demo-example', search: 'srch-review-demo-example' }
param capability_provisioning = { approved: true, evidence_reference: 'EXAMPLE-NOT-PREVIEW-OR-LIVE-GRANT-VERIFICATION' }
