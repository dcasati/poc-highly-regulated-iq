targetScope = 'subscription'
import { us_region } from './types.bicep'

@description('Generic PoC branding, 3-16 lowercase letters/digits/single hyphens; not a live deployment name.')
@minLength(3)
@maxLength(16)
param project_name string

@description('Explicit approved supported resource region permitted by deployment validation rules. Processing residency needs separate verification.')
param location us_region

var boundaries = ['connectivity', 'state', 'foundation', 'scenario']
resource groups 'Microsoft.Resources/resourceGroups@2024-03-01' = [for boundary in boundaries: {
  name: 'rg-${project_name}-${boundary}'
  location: location
  tags: {
    project: project_name
    managed_by: 'Bicep'
    purpose: boundary
  }
}]
output resource_groups array = [for (boundary, i) in boundaries: groups[i].name]
