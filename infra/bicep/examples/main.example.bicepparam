using '../main.bicep'
param project_name = 'review-demo'
param location = 'eastus2'
param vnet_cidr = '10.80.0.0/16'
param administration = { approved: true, evidence_reference: 'EXAMPLE-synthetic-only-network-approval' }
param ssh_public_key = 'ssh-ed25519 EXAMPLE-not-a-real-public-key'
param image_version = '24.04.202501020'
param administration_egress = []
param platform_destinations = {
  runtime: []
  build: []
  verification: { approved: true, evidence_reference: 'EXAMPLE-exact-egress-review-required' }
}
param models = {
  chat: { name: 'gpt-5.2', version: '2025-12-11', sku: 'DataZoneStandard', capacity: 10 }
  embedding: { name: 'text-embedding-3-large', version: '1', sku: 'DataZoneStandard', capacity: 10 }
}
param caller_principal_id = '11111111-1111-4111-8111-111111111111'
param caller_principal_type = 'User'
