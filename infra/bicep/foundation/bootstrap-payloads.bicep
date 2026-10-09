import { approval } from '../types.bicep'
@description('Verified successful native host, runtime store grants and supported CU model/default mappings. Not application readiness.')
param private_dependencies approval
@description('Actual supported completion/embedding model names and their pinned foundation deployment names.')
param models {
  completion: { name: string, deployment: string }
  embedding: { name: string, deployment: string }
}
@description('GET/readback of unrelated CU modelDeployments; preserve them on PATCH. Never pass credentials.')
param existing_model_deployments { *: string } = {}
@description('Actual native policy ARM ID from the Bicep foundation output, never just its display name.')
@minLength(1)
param chat_rai_policy_id string
@description('Reviewed agent name; existing agents get a NEW version, never deletion of earlier versions.')
param agent_name string = 'exempt-agent'
@description('Verified existing agent description/metadata and prompt-definition options to preserve; leave empty only for a new agent.')
param preserved_agent object = {}

var definition = union(preserved_agent.?definition ?? {}, {
  kind: 'prompt'
  model: models.completion.deployment
  instructions: loadTextContent('./review-agent.instructions.txt')
  tools: []
  rai_config: union(preserved_agent.?definition.?rai_config ?? {}, { rai_policy_name: chat_rai_policy_id })
})
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
output agent_request object = {
  method: 'POST'
  path: '/agents/${agent_name}/versions?api-version=2025-11-15-preview'
  body: union(preserved_agent, { definition: definition })
}
output new_agent_request object = {
  method: 'POST'
  path: '/agents?api-version=2025-11-15-preview'
  body: union(preserved_agent, { name: agent_name, definition: definition })
}
output verification_reference string = private_dependencies.evidence_reference
