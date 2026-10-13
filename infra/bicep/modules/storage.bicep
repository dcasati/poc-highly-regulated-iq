import { us_region } from '../types.bicep'
@description('New globally unique storage account name.')
param name string
@description('Explicit approved supported Azure region permitted by deployment validation rules.')
param location us_region
@description('Soft-delete retention, not locked immutable retention.')
@minValue(7)
@maxValue(365)
param retention_days int = 30

resource account 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: name
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    isLocalUserEnabled: false
    allowCrossTenantReplication: false
    encryption: {
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: true
      services: {
        blob: { enabled: true, keyType: 'Account' }
        file: { enabled: true, keyType: 'Account' }
      }
    }
    networkAcls: { defaultAction: 'Deny', bypass: 'None', ipRules: [], virtualNetworkRules: [] }
  }
}
resource blob 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' = {
  parent: account
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: { enabled: true, days: retention_days }
    containerDeleteRetentionPolicy: { enabled: true, days: retention_days }
  }
}
output id string = account.id
output name string = account.name
output blob_endpoint string = account.properties.primaryEndpoints.blob
