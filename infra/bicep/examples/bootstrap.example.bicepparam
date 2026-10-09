using '../foundation/bootstrap-payloads.bicep'
param private_dependencies = { approved: true, evidence_reference: 'EXAMPLE-private-host-grants-supported-models-readback' }
param models = {
  completion: { name: 'gpt-5.2', deployment: 'chat' }
  embedding: { name: 'text-embedding-3-large', deployment: 'embedding' }
}
param chat_rai_policy_id = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-review-demo-foundation/providers/Microsoft.CognitiveServices/accounts/ai-review-demo/raiPolicies/chat-prompt-shields'
