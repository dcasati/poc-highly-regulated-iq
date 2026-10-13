import { approval } from '../types.bicep'
@description('Verified private model access and supported CU model/default mappings. Not application readiness.')
param private_dependencies approval
@description('Actual supported completion/embedding model names and their pinned foundation deployment names.')
param models {
  completion: { name: string, deployment: string }
  embedding: { name: string, deployment: string }
}
@description('GET/readback of unrelated CU modelDeployments; preserve them on PATCH. Never pass credentials.')
param existing_model_deployments { *: string } = {}
output content_defaults_request object = {
  method: 'PATCH'
  path: '/contentunderstanding/defaults?api-version=2025-11-01'
  body: {
    modelDeployments: union(existing_model_deployments, {
      '${models.completion.name}': models.completion.deployment
      '${models.embedding.name}': models.embedding.deployment
      'prebuilt-analyzer-completion': models.completion.deployment
      'prebuilt-analyzer-completion-mini': models.completion.deployment
      'prebuilt-analyzer-embedding': models.embedding.deployment
    })
  }
}
output verification_reference string = private_dependencies.evidence_reference
