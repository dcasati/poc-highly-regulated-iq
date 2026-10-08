using '../scenario/aks-manifests.bicep'
param project_name = 'review-demo'
param runtime = {
  approved: true
  platform_evidence: 'EXAMPLE-NOT-PLATFORM-ACCEPTANCE'
  image_evidence: 'EXAMPLE-NOT-IMAGE-ACCEPTANCE'
  transport_evidence: 'EXAMPLE-NOT-TRANSPORT-ACCEPTANCE'
  knowledge: { approved: true, evidence_reference: 'EXAMPLE-NOT-KNOWLEDGE-READINESS' }
  identity: {
    tenant_id: '33333333-3333-4333-8333-333333333333'
    spa_client_id: '44444444-4444-4444-8444-444444444444'
    api_client_id: '55555555-5555-4555-8555-555555555555'
  }
  image_algorithm: 'sha256'
  image_hash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
}
param application = {
  blob_endpoint: 'https://stexampleapplication.blob.core.windows.net'
  content_endpoint: 'https://ai-review-demo-example.services.ai.azure.com'
  search_endpoint: 'https://srch-review-demo-example.search.windows.net'
  project_endpoint: 'https://ai-review-demo-example.services.ai.azure.com/api/projects/review-demo-review'
  agent_name: 'exempt-agent'
  analyzer_id: 'application-review'
  field_names: ['ApplicantName', 'Description', 'ReferenceNumber', 'RequestedCategory', 'SignaturePresent', 'SupportingDocuments']
  processing_location: 'geography'
  confidence_threshold: '0.9'
}
param platform = { registry_login_server: 'acrexamplereview.azurecr.io', identity_client_id: '66666666-6666-4666-8666-666666666666' }
param ingress = { hostname: 'review.example.internal', private_ip: '10.80.1.10', mesh_revision: 'REPLACE-WITH-SUPPORTED-REVISION', namespace: 'aks-istio-ingress', tls_secret_name: 'approved-review-tls' }
param approved_https_cidrs = ['10.80.2.0/24']
