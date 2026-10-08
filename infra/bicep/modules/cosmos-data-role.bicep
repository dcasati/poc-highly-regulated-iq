@description('Existing native-agent Cosmos account, never application/state data.')
param account_name string
@description('Discovered existing service-created database name.')
param database_name string
@description('Verified runtime principal GUID.')
param principal_id string
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2025-04-15' existing = { name: account_name }
resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2025-04-15' existing = { parent: cosmos, name: database_name }
resource role 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2025-04-15' = {
  parent: cosmos
  name: guid(cosmos.id, database_name, principal_id, 'data-contributor')
  properties: {
    principalId: principal_id
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: '${cosmos.id}/dbs/${database.properties.resource.id}'
  }
}
