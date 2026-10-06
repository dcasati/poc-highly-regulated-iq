resource "azurerm_container_app_environment" "app" {
  count                          = var.hosting == "container_apps" ? 1 : 0
  name                           = "cae-${local.prefix}"
  resource_group_name            = azurerm_resource_group.scenario.name
  location                       = var.location
  infrastructure_subnet_id       = data.azurerm_subnet.runtime.id
  internal_load_balancer_enabled = true
  public_network_access          = "Disabled"
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
  tags = local.tags
}
resource "azurerm_private_dns_zone" "app" {
  count               = var.hosting == "container_apps" ? 1 : 0
  name                = azurerm_container_app_environment.app[0].default_domain
  resource_group_name = azurerm_resource_group.scenario.name
}
resource "azurerm_private_dns_zone_virtual_network_link" "app" {
  count               = var.hosting == "container_apps" ? 1 : 0
  name                = "runtime"
  private_dns_zone_id = azurerm_private_dns_zone.app[0].id
  virtual_network_id  = data.azurerm_virtual_network.existing.id
}
resource "azurerm_private_dns_a_record" "app" {
  count               = var.hosting == "container_apps" ? 1 : 0
  name                = "*"
  private_dns_zone_id = azurerm_private_dns_zone.app[0].id
  ttl                 = 300
  records             = [azurerm_container_app_environment.app[0].static_ip_address]
}
resource "azurerm_container_app" "app" {
  count                        = var.hosting == "container_apps" && var.deploy_runtime ? 1 : 0
  name                         = "review-${var.project_name}"
  resource_group_name          = azurerm_resource_group.scenario.name
  container_app_environment_id = azurerm_container_app_environment.app[0].id
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }
  registry {
    server   = azurerm_container_registry.app.login_server
    identity = azurerm_user_assigned_identity.app.id
  }
  ingress {
    external_enabled           = true
    allow_insecure_connections = false
    target_port                = 8080
    transport                  = "http"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
  template {
    min_replicas = 1
    max_replicas = 3
    container {
      name   = "review"
      image  = local.image
      cpu    = 1
      memory = "2Gi"
      dynamic "env" {
        for_each = local.portal_env
        content {
          name  = env.key
          value = env.value
        }
      }
      liveness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/health/live"
      }
      readiness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/health/ready"
      }
    }
  }
  tags = local.tags
  depends_on = [
    terraform_data.gates, azurerm_private_endpoint.registry, azurerm_role_assignment.app_pull,
    azurerm_role_assignment.app_storage, azurerm_role_assignment.app_content,
    azurerm_role_assignment.app_project, azurerm_role_assignment.app_search
  ]
}

resource "azurerm_user_assigned_identity" "cluster" {
  count               = var.hosting == "aks" ? 1 : 0
  name                = "id-${local.prefix}-cluster"
  resource_group_name = azurerm_resource_group.scenario.name
  location            = var.location
}
resource "azurerm_role_assignment" "cluster_network" {
  count                = var.hosting == "aks" ? 1 : 0
  scope                = data.azurerm_virtual_network.existing.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster[0].principal_id
}
resource "azurerm_kubernetes_cluster" "app" {
  count                               = var.hosting == "aks" ? 1 : 0
  name                                = "aks-${local.prefix}"
  resource_group_name                 = azurerm_resource_group.scenario.name
  location                            = var.location
  dns_prefix                          = local.prefix
  kubernetes_version                  = var.aks.kubernetes_version
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = false
  local_account_disabled              = true
  oidc_issuer_enabled                 = true
  workload_identity_enabled           = true
  sku_tier                            = "Standard"
  node_provisioning_profile {
    mode = "Manual"
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster[0].id]
  }
  azure_active_directory_role_based_access_control {
    tenant_id          = var.identity.tenant_id
    azure_rbac_enabled = true
  }
  default_node_pool {
    name                         = "system"
    node_count                   = var.aks.node_count
    vm_size                      = var.aks.vm_size
    os_sku                       = var.aks.os_sku
    fips_enabled                 = true
    only_critical_addons_enabled = true
    vnet_subnet_id               = data.azurerm_subnet.runtime.id
    temporary_name_for_rotation  = "sysrotate"
  }
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    outbound_type       = "userDefinedRouting"
    pod_cidr            = var.aks.pod_cidr
    service_cidr        = var.aks.service_cidr
    dns_service_ip      = var.aks.dns_service_ip
  }
  service_mesh_profile {
    mode                             = "Istio"
    revisions                        = [var.aks.mesh_revision]
    internal_ingress_gateway_enabled = true
    external_ingress_gateway_enabled = false
  }
  tags       = local.tags
  depends_on = [azurerm_role_assignment.cluster_network, terraform_data.gates]
}
resource "azurerm_kubernetes_cluster_node_pool" "app" {
  count                 = var.hosting == "aks" ? 1 : 0
  name                  = "fipsapp"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.app[0].id
  vm_size               = var.aks.vm_size
  node_count            = var.aks.node_count
  os_sku                = var.aks.os_sku
  fips_enabled          = true
  mode                  = "User"
  vnet_subnet_id        = data.azurerm_subnet.runtime.id
  node_labels           = { workload = "review", compliance = "fips" }
  node_taints           = ["workload=review:NoSchedule"]
}
resource "azurerm_role_assignment" "cluster_pull" {
  count                = var.hosting == "aks" ? 1 : 0
  scope                = azurerm_container_registry.app.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.app[0].kubelet_identity[0].object_id
}
resource "azurerm_role_assignment" "cluster_deployer" {
  count                = var.hosting == "aks" ? 1 : 0
  scope                = azurerm_kubernetes_cluster.app[0].id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
resource "azurerm_federated_identity_credential" "app" {
  count                     = var.hosting == "aks" ? 1 : 0
  name                      = "review"
  user_assigned_identity_id = azurerm_user_assigned_identity.app.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.app[0].oidc_issuer_url
  subject                   = "system:serviceaccount:review:review"
}
