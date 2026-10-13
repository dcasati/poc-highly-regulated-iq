using '../foundation/bootstrap-payloads.bicep'
param private_dependencies = { approved: true, evidence_reference: 'EXAMPLE-private-host-grants-supported-models-readback' }
param models = {
  completion: { name: 'gpt-5.2', deployment: 'chat' }
  embedding: { name: 'text-embedding-3-large', deployment: 'embedding' }
}
