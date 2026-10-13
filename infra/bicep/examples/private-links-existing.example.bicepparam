using '../scenario/private-links.bicep'
param project_name = 'review-demo'
param search_name = 'srch-review-demo-example'
param foundry = { resource_group_name: 'rg-review-demo-foundation', name: 'ai-review-demo-example' }
param existing_content_links = { foundry_account: 'verified-existing-processing', cognitiveservices_account: 'verified-existing-billing' }
