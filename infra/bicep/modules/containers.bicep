@description('Existing PoC storage account; account settings remain untouched.')
param account_name string
@description('New boundary-owned containers only, never native Agent Service stores.')
param container_names string[]
resource account 'Microsoft.Storage/storageAccounts@2025-06-01' existing = { name: account_name }
resource blob 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' existing = { parent: account, name: 'default' }
resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = [for name in container_names: {
  parent: blob
  name: name
  properties: { publicAccess: 'None' }
}]
