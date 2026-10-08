import { reference } from '../types.bicep'
@description('Generic PoC branding.')
param project_name string
@description('Existing private Search in this resource group.')
param search_name string
@description('Verified existing foundation Foundry account.')
param foundry reference
@description('Existing link names keyed by group, inspected first to prevent duplicate target/group pairs. Null means request a new owner-approved link.')
param existing_content_links {
  foundry_account: string?
  cognitiveservices_account: string?
} = { foundry_account: null, cognitiveservices_account: null }
resource search 'Microsoft.Search/searchServices@2025-05-01' existing = { name: search_name }
var groups = ['foundry_account', 'cognitiveservices_account']
var names = [existing_content_links.?foundry_account, existing_content_links.?cognitiveservices_account]
resource requests 'Microsoft.Search/searchServices/sharedPrivateLinkResources@2025-05-01' = [for (group, i) in groups: if (names[i] == null) {
  parent: search
  name: '${project_name}-${replace(group, '_', '-')}'
  properties: {
    groupId: group
    privateLinkResourceId: resourceId(foundry.resource_group_name, 'Microsoft.CognitiveServices/accounts', foundry.name)
    requestMessage: 'Target-owner approval required; private-link creation is not approval or knowledge readiness.'
  }
}]
