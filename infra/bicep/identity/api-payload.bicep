@description('Selected single-directory solution branding, not an existing registration to adopt.')
param project_name string
@description('Explicit approved directory GUID; native operator must verify the authenticated directory matches before Graph writes.')
@minLength(36)
@maxLength(36)
param tenant_id string
@description('Nonsecret GUID of the explicitly authorized registration owner, verified in the selected directory.')
param owner_object_id string
var scope_id = guid(project_name, 'access_as_user')
var roles = [for name in ['Caseworker', 'Reviewer']: {
  id: guid(project_name, 'review-role', name)
  value: name
  displayName: name
  description: 'Perform ${name} actions in the private document-review portal; no eligibility authority.'
  allowedMemberTypes: ['User']
  isEnabled: true
}]
output api_request object = {
  method: 'POST'
  path: '/v1.0/applications'
  body: {
    displayName: '${project_name}-review-api'
    signInAudience: 'AzureADMyOrg'
    'owners@odata.bind': ['https://graph.microsoft.com/v1.0/directoryObjects/${owner_object_id}']
    api: {
      requestedAccessTokenVersion: 2
      oauth2PermissionScopes: [{
        id: scope_id
        value: 'access_as_user'
        type: 'User'
        isEnabled: true
        adminConsentDisplayName: 'Access the document-review API as the signed-in user'
        adminConsentDescription: 'Access only case actions authorized by assigned caseworker/reviewer roles.'
        userConsentDisplayName: 'Access the document-review API'
        userConsentDescription: 'Use this private portal with assigned roles.'
      }]
    }
    appRoles: roles
  }
}
output scope_id string = scope_id
output role_ids object = { Caseworker: roles[0].id, Reviewer: roles[1].id }
output expected_tenant_id string = tenant_id
