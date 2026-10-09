@description('Selected single-directory solution branding.')
param project_name string
@description('Explicit approved directory GUID; verify CLI/Graph authentication matches.')
@minLength(36)
@maxLength(36)
param tenant_id string
@description('Approved owner GUID in the selected directory.')
param owner_object_id string
@description('Actual API application/client ID from native Graph creation/readback, not its object ID.')
param api_client_id string
@description('Exact private HTTPS portal redirect URI(s), reviewed after the ACA environment DNS exists. No wildcard or localhost.')
@minLength(1)
param redirect_uris string[]
output spa_request object = {
  method: 'POST'
  path: '/v1.0/applications'
  body: {
    displayName: '${project_name}-review-spa'
    signInAudience: 'AzureADMyOrg'
    'owners@odata.bind': ['https://graph.microsoft.com/v1.0/directoryObjects/${owner_object_id}']
    spa: { redirectUris: redirect_uris }
    requiredResourceAccess: [{
      resourceAppId: api_client_id
      resourceAccess: [{ id: guid(project_name, 'access_as_user'), type: 'Scope' }]
    }]
    publicClient: { redirectUris: [] }
    web: { implicitGrantSettings: { enableAccessTokenIssuance: false, enableIdTokenIssuance: false } }
  }
}
output expected_tenant_id string = tenant_id
