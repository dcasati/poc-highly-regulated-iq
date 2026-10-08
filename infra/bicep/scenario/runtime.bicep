import { us_region, runtime_approval } from '../types.bicep'
import { application_config, portal_environment } from './application.bicep'
@description('Generic PoC branding.')
param project_name string
@description('Explicit US region.')
param location us_region
@description('Actual previously provisioned private Container Apps environment, registry and application identity.')
param platform { environment_name: string, registry_name: string, identity_name: string }
@description('Mandatory exact image/platform/transport acceptance, knowledge readiness and real approved browser registrations. No false/default approval is offered here.')
param runtime runtime_approval
@description('Verified private endpoints and existing tools-disabled prompt agent. Fields match the separately reviewed custom analyzer.')
param application application_config
resource environment 'Microsoft.App/managedEnvironments@2025-07-01' existing = { name: platform.environment_name }
resource registry 'Microsoft.ContainerRegistry/registries@2025-04-01' existing = { name: platform.registry_name }
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = { name: platform.identity_name }
resource app 'Microsoft.App/containerApps@2025-01-01' = {
  name: 'review-${project_name}'
  location: location
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${identity.id}': {} } }
  tags: { project: project_name, platform_evidence: runtime.platform_evidence, image_evidence: runtime.image_evidence, transport_evidence: runtime.transport_evidence, knowledge_evidence: runtime.knowledge.evidence_reference }
  properties: {
    managedEnvironmentId: environment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      registries: [{ server: registry.properties.loginServer, identity: identity.id }]
      ingress: { external: true, allowInsecure: false, targetPort: 8080, transport: 'http', traffic: [{ latestRevision: true, weight: 100 }] }
    }
    template: {
      scale: { minReplicas: 1, maxReplicas: 3 }
      containers: [{
        name: 'review'
        image: '${registry.properties.loginServer}/review-portal@${runtime.image_algorithm}:${runtime.image_hash}'
        resources: { cpu: 1, memory: '2Gi' }
        env: portal_environment(project_name, runtime, application, identity.properties.clientId)
        probes: [
          { type: 'Liveness', httpGet: { path: '/health/live', port: 8080, scheme: 'HTTP' } }
          { type: 'Readiness', httpGet: { path: '/health/ready', port: 8080, scheme: 'HTTP' } }
        ]
      }]
    }
  }
}
output portal_url string = 'https://${app.properties.configuration.ingress.fqdn}/'
