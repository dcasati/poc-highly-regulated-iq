using '../knowledge/payloads.bicep'
param project_name = 'review-demo'
param storage = { resource_group_name: 'rg-review-demo-foundation', name: 'stexampleapplication' }
param content_endpoint = 'https://ai-review-demo-example.services.ai.azure.com'
param analyzer_models = { completion: 'gpt-5.2', embedding: 'text-embedding-3-large' }
param private_dependencies = { approved: true, evidence_reference: 'EXAMPLE-NOT-LINK-DEFAULTS-OR-PROCESSING-VERIFICATION' }
