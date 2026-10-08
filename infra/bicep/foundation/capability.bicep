import { approval } from '../types.bicep'
@description('Existing account name.')
param account_name string
@description('Existing project child name.')
param project_child_name string
@description('Verified nonshared AAD connection names, not ARM IDs.')
param connections { blob: string, cosmos: string, search: string }
@description('Separate preview acceptance and verification of actual project identity, successful live grants and private connections.')
param capability_provisioning approval
resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = { name: account_name }
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = { parent: account, name: project_child_name }
resource host 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: project
  name: 'agents'
  properties: {
    // Official BYO-VNet sample requires this field, missing from the published preview type.
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
    storageConnections: [connections.blob]
    threadStorageConnections: [connections.cosmos]
    vectorStoreConnections: [connections.search]
  }
}
output host_id string = host.id
output verification_reference string = capability_provisioning.evidence_reference
