data "azurerm_client_config" "current" {}

data "azurerm_virtual_network" "poc" {
  name                = var.network.name
  resource_group_name = var.network.resource_group_name
}

data "azurerm_subnet" "endpoints" {
  name                 = var.network.endpoint_subnet_name
  virtual_network_name = data.azurerm_virtual_network.poc.name
  resource_group_name  = data.azurerm_virtual_network.poc.resource_group_name
}

data "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.network.blob_dns_resource_group
}

data "azapi_resource" "blob_dns_metadata" {
  type                   = "Microsoft.Network/privateDnsZones@2024-06-01"
  resource_id            = data.azurerm_private_dns_zone.blob.id
  response_export_values = ["tags"]
}

locals {
  suffix      = substr(sha256("foundation/${data.azurerm_client_config.current.subscription_id}/${var.project_name}"), 0, 6)
  prefix      = "${var.project_name}-${local.suffix}"
  storage_key = substr(replace(var.project_name, "-", ""), 0, 12)
  tags        = merge(var.tags, { project = var.project_name, environment = "poc", purpose = "ai-foundation", managed_by = "Terraform" })
}

resource "terraform_data" "gates" {
  lifecycle {
    precondition {
      condition = (
        lower(data.azurerm_client_config.current.subscription_id) == lower(var.expected_context.subscription_id) &&
        lower(data.azurerm_client_config.current.tenant_id) == lower(var.expected_context.tenant_id) &&
        lower(data.azurerm_client_config.current.object_id) == lower(var.expected_context.object_id)
      )
      error_message = "The active subscription, directory and deployment principal must match the verified isolated CLI context."
    }
    precondition {
      condition     = var.capability_preview_approved
      error_message = "Explicit capability-settings preview acceptance is required; it does not approve an apply or production use."
    }
    precondition {
      condition = (
        data.azurerm_virtual_network.poc.location == var.location &&
        try(data.azurerm_virtual_network.poc.tags["project"], "") == var.project_name &&
        length(data.azurerm_virtual_network.poc.address_space) == 1 &&
        can(regex("^10\\.[0-9]+\\.0\\.0/16$", data.azurerm_virtual_network.poc.address_space[0]))
      )
      error_message = "Use the PoC-owned, same-region canonical connectivity VNet; unrelated infrastructure is excluded."
    }
    precondition {
      condition = (
        length(data.azurerm_subnet.endpoints.address_prefixes) == 1 &&
        data.azurerm_subnet.endpoints.address_prefixes[0] == cidrsubnet(data.azurerm_virtual_network.poc.address_space[0], 8, 2) &&
        try(data.azapi_resource.blob_dns_metadata.output.tags["project"], "") == var.project_name
      )
      error_message = "The endpoint subnet and Blob DNS zone must match the separately owned PoC backend."
    }
    precondition {
      condition     = !var.provision_project || var.private_connectivity_verified
      error_message = "Verify private DNS, HTTPS, keyless stores and caller-role propagation before provisioning the project."
    }
  }
}

resource "azurerm_resource_group" "foundation" {
  name     = "rg-${var.project_name}-foundation"
  location = var.location
  tags     = local.tags
  lifecycle { prevent_destroy = true }
  depends_on = [terraform_data.gates]
}
