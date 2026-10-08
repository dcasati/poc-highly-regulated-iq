data "azurerm_resource_group" "registry" {
  name = var.registry.resource_group_name
}

data "azapi_resource" "registry" {
  type      = "Microsoft.ContainerRegistry/registries@2025-04-01"
  name      = var.registry.name
  parent_id = data.azurerm_resource_group.registry.id
  response_export_values = [
    "location", "sku.name", "properties.loginServer",
    "properties.publicNetworkAccess", "properties.privateEndpointConnections"
  ]
}

data "azurerm_virtual_network" "build" {
  name                = var.build_subnet.virtual_network_name
  resource_group_name = var.build_subnet.resource_group_name
}

data "azurerm_subnet" "build" {
  name                 = var.build_subnet.name
  virtual_network_name = data.azurerm_virtual_network.build.name
  resource_group_name  = data.azurerm_virtual_network.build.resource_group_name
}

locals {
  pool_tags = merge(var.tags, {
    project    = var.project_name
    managed_by = "Terraform"
    component  = "container-build"
  })
}

resource "azurerm_container_registry_agent_pool" "build" {
  name                      = "${replace(var.project_name, "-", "")}pool"
  location                  = var.location
  resource_group_name       = data.azurerm_resource_group.registry.name
  container_registry_name   = var.registry.name
  virtual_network_subnet_id = data.azurerm_subnet.build.id
  tier                      = var.tier
  instance_count            = var.instance_count
  tags                      = local.pool_tags

  lifecycle {
    # AzureRM 5.8.0 omits tags on pool updates; the ARM tags child owns them.
    ignore_changes = [tags]
    precondition {
      condition     = var.preview_approved
      error_message = "ACR agent pools are a preview. Obtain organization approval before provisioning."
    }
    precondition {
      condition     = data.azapi_resource.registry.output.sku.name == "Premium"
      error_message = "A dedicated ACR agent pool requires an existing Premium registry; this root will not upgrade it."
    }
    precondition {
      condition     = data.azapi_resource.registry.output.properties.publicNetworkAccess == "Disabled"
      error_message = "The selected registry must remain private. This root does not change public access or firewall rules."
    }
    precondition {
      condition = anytrue([
        for connection in data.azapi_resource.registry.output.properties.privateEndpointConnections :
        connection.properties.privateLinkServiceConnectionState.status == "Approved"
      ])
      error_message = "The existing registry needs an approved private endpoint reachable from the build subnet."
    }
    precondition {
      condition = (
        replace(lower(data.azapi_resource.registry.output.location), " ", "") == var.location &&
        data.azurerm_virtual_network.build.location == var.location
      )
      error_message = "Choose the approved registry/VNet region for the new build pool."
    }
  }

}

resource "azapi_resource" "pool_tags" {
  type      = "Microsoft.Resources/tags@2021-04-01"
  name      = "default"
  parent_id = azurerm_container_registry_agent_pool.build.id
  body = {
    properties = {
      tags = local.pool_tags
    }
  }
}
