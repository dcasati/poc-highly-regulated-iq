import { us_region, reference } from '../types.bicep'
@description('Generic PoC branding.')
param project_name string
@description('Explicit approved supported Azure region permitted by deployment validation rules.')
param location us_region
@description('Approved AKS versions, FIPS OS/VM compatibility, mesh and nonoverlapping network ranges.')
param config {
  kind: 'aks'
  kubernetes_version: string
  os_sku: 'AzureLinux3' | 'Ubuntu' | 'Ubuntu2204'
  vm_size: string
  mesh_revision: string
  @minValue(2)
  node_count: int
  pod_cidr: string
  service_cidr: string
  dns_service_ip: string
  deployer_principal_id: string
}
@description('Undelegated node subnet, verified existing VNet and functional reviewed UDR egress.')
param network { runtime_subnet_id: string, vnet: reference }
@description('Existing private registry and application identity in this resource group.')
param platform { registry_name: string, identity_name: string }
@description('Nonsensitive hosting dependency approval evidence.')
param verification string
var prefix = '${project_name}-${take(uniqueString(subscription().id, project_name, 'scenario'), 8)}'
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = { name: 'id-${prefix}-cluster', location: location }
module network_role '../modules/service-roles.bicep' = {
  name: 'cluster-network-role'
  scope: resourceGroup(network.vnet.resource_group_name)
  params: { kind: 'network', name: network.vnet.name, principal_id: identity.properties.principalId, role_id: '4d97b98b-1d4f-4787-a291-c67834d212e7' }
}
resource cluster 'Microsoft.ContainerService/managedClusters@2025-05-01' = {
  name: 'aks-${prefix}'
  location: location
  sku: { name: 'Base', tier: 'Standard' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${identity.id}': {} } }
  tags: { project: project_name, verification: verification }
  properties: {
    dnsPrefix: prefix
    kubernetesVersion: config.kubernetes_version
    enableRBAC: true
    disableLocalAccounts: true
    aadProfile: { managed: true, enableAzureRBAC: true, tenantID: subscription().tenantId }
    apiServerAccessProfile: { enablePrivateCluster: true, enablePrivateClusterPublicFQDN: false }
    oidcIssuerProfile: { enabled: true }
    securityProfile: { workloadIdentity: { enabled: true } }
    nodeProvisioningProfile: { mode: 'Manual' }
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: config.node_count
        vmSize: config.vm_size
        osType: 'Linux'
        osSKU: config.os_sku
        enableFIPS: true
        vnetSubnetID: network.runtime_subnet_id
        type: 'VirtualMachineScaleSets'
        nodeTaints: ['CriticalAddonsOnly=true:NoSchedule']
      }
      {
        name: 'fipsapp'
        mode: 'User'
        count: config.node_count
        vmSize: config.vm_size
        osType: 'Linux'
        osSKU: config.os_sku
        enableFIPS: true
        vnetSubnetID: network.runtime_subnet_id
        type: 'VirtualMachineScaleSets'
        nodeLabels: { workload: 'review', compliance: 'fips' }
        nodeTaints: ['workload=review:NoSchedule']
      }
    ]
    networkProfile: { networkPlugin: 'azure', networkPluginMode: 'overlay', networkDataplane: 'cilium', networkPolicy: 'cilium', outboundType: 'userDefinedRouting', podCidr: config.pod_cidr, serviceCidr: config.service_cidr, dnsServiceIP: config.dns_service_ip }
    serviceMeshProfile: { mode: 'Istio', istio: { revisions: [config.mesh_revision], components: { ingressGateways: [{ mode: 'Internal', enabled: true }] } } }
  }
  dependsOn: [network_role]
}
module pull '../modules/service-roles.bicep' = {
  name: 'kubelet-private-registry-pull'
  params: { kind: 'registry', name: platform.registry_name, principal_id: cluster.properties.identityProfile.kubeletidentity.objectId, role_id: '7f951dda-4ed3-4680-a7ca-43fe172d538d' }
}
module deployer '../modules/service-roles.bicep' = {
  name: 'cluster-scoped-deployer'
  params: { kind: 'cluster', name: cluster.name, principal_id: config.deployer_principal_id, principal_type: 'User', role_id: 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b' }
}
resource app 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = { name: platform.identity_name }
resource federation 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = {
  parent: app
  name: 'review'
  properties: { audiences: ['api://AzureADTokenExchange'], issuer: cluster.properties.oidcIssuerProfile.issuerURL, subject: 'system:serviceaccount:review:review' }
}
output cluster_name string = cluster.name
