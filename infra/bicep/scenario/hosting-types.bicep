@export()
@discriminator('kind')
type hosting_config = {
  kind: 'container_apps'
} | {
  kind: 'aks'
  @minLength(1)
  kubernetes_version: string
  os_sku: 'AzureLinux3' | 'Ubuntu' | 'Ubuntu2204'
  @minLength(1)
  vm_size: string
  @minLength(1)
  mesh_revision: string
  @minValue(2)
  node_count: int
  pod_cidr: string
  service_cidr: string
  dns_service_ip: string
  deployer_principal_id: string
}
