@description('Selected single-directory solution branding.')
param project_name string
@description('Explicit approved directory GUID; verify CLI/Graph authentication matches.')
@minLength(36)
@maxLength(36)
param tenant_id string
@description('Actual API application object ID and application/client ID returned by Graph.')
param api { object_id: string, client_id: string }
@description('Actual SPA application/client ID returned by Graph.')
param spa_client_id string
@description('Approved owner object GUID in the selected directory.')
param owner_object_id string
output graph_requests array = [
  {
    method: 'PATCH'
    path: '/v1.0/applications/${api.object_id}'
    body: {
      identifierUris: ['api://${api.client_id}']
      api: {
        requestedAccessTokenVersion: 2
        oauth2PermissionScopes: [{
          id: guid(project_name, 'access_as_user')
          value: 'access_as_user'
          type: 'User'
          isEnabled: true
          adminConsentDisplayName: 'Access the document-review API as the signed-in user'
          adminConsentDescription: 'Access only case actions authorized by assigned caseworker/reviewer roles.'
          userConsentDisplayName: 'Access the document-review API'
          userConsentDescription: 'Use this private portal with assigned roles.'
        }]
        preAuthorizedApplications: [{ appId: spa_client_id, delegatedPermissionIds: [guid(project_name, 'access_as_user')] }]
      }
    }
  }
  {
    method: 'POST'
    path: '/v1.0/servicePrincipals'
    body: {
      appId: api.client_id
      appRoleAssignmentRequired: true
      'owners@odata.bind': ['https://graph.microsoft.com/v1.0/directoryObjects/${owner_object_id}']
    }
  }
  {
    method: 'POST'
    path: '/v1.0/servicePrincipals'
    body: {
      appId: spa_client_id
      'owners@odata.bind': ['https://graph.microsoft.com/v1.0/directoryObjects/${owner_object_id}']
    }
  }
]
output role_ids object = {
  Caseworker: guid(project_name, 'review-role', 'Caseworker')
  Reviewer: guid(project_name, 'review-role', 'Reviewer')
}
output expected_tenant_id string = tenant_id
