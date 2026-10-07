data "azurerm_client_config" "current" {}

data "azurerm_virtual_network" "poc" {
  name                = var.connectivity_network.name
  resource_group_name = var.connectivity_network.resource_group_name
}

locals {
  suffix       = substr(sha256("terraform-state/${data.azurerm_client_config.current.subscription_id}/${var.project_name}"), 0, 6)
  account_name = "st${replace(var.project_name, "-", "")}${local.suffix}"
  name         = "${var.project_name}-state"
  tags         = merge(var.tags, { project = var.project_name, environment = "poc", purpose = "terraform-state", managed_by = "Terraform" })
}

resource "terraform_data" "approval" {
  lifecycle {
    precondition {
      condition     = var.backend_bootstrap_approved
      error_message = "Obtain explicit approval for the encrypted-host, owner-only local backend bootstrap. Apply and state migration need separate approvals."
    }
    precondition {
      condition     = data.azurerm_virtual_network.poc.location == var.location && try(data.azurerm_virtual_network.poc.tags["project"], "") == var.project_name
      error_message = "The VNet must be the verified PoC-owned network in the selected US region."
    }
    precondition {
      condition     = length(data.azurerm_virtual_network.poc.address_space) == 1 && can(regex("^10\\.[0-9]+\\.0\\.0/16$", data.azurerm_virtual_network.poc.address_space[0]))
      error_message = "Use the connectivity root's single canonical 10.x.0.0/16; its third /24 is reserved for this PoC's private endpoints."
    }
  }
}

resource "azurerm_resource_group" "state" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
  lifecycle { prevent_destroy = true }
  depends_on = [terraform_data.approval]
}

resource "azurerm_storage_account" "state" {
  name                              = local.account_name
  resource_group_name               = azurerm_resource_group.state.name
  location                          = var.location
  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  access_tier                       = "Hot"
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  public_network_access             = "Disabled"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  local_user_enabled                = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  tags                              = local.tags
  network_rules {
    default_action = "Deny"
    bypass         = ["None"]
  }
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = var.retention_days
    }
    container_delete_retention_policy {
      days = var.retention_days
    }
  }
  lifecycle { prevent_destroy = true }
}

resource "azurerm_storage_container" "state" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
  lifecycle { prevent_destroy = true }
}

resource "azurerm_role_assignment" "deployment_state" {
  scope                = "${azurerm_storage_account.state.id}/blobServices/default/containers/${azurerm_storage_container.state.name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = var.deployment_principal_type
}

resource "azurerm_subnet" "endpoints" {
  name                            = "snet-${var.project_name}-private-endpoints"
  resource_group_name             = data.azurerm_virtual_network.poc.resource_group_name
  virtual_network_name            = data.azurerm_virtual_network.poc.name
  address_prefixes                = [cidrsubnet(data.azurerm_virtual_network.poc.address_space[0], 8, 2)]
  default_outbound_access_enabled = false
  lifecycle { prevent_destroy = true }
  depends_on = [terraform_data.approval]
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.state.name
  tags                = local.tags
  lifecycle { prevent_destroy = true }
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                 = "link-${var.project_name}"
  private_dns_zone_id  = azurerm_private_dns_zone.blob.id
  virtual_network_id   = data.azurerm_virtual_network.poc.id
  registration_enabled = false
  tags                 = local.tags
}

resource "azurerm_private_endpoint" "state" {
  name                = "pe-${local.name}-blob"
  resource_group_name = azurerm_resource_group.state.name
  location            = var.location
  subnet_id           = azurerm_subnet.endpoints.id
  tags                = local.tags
  private_service_connection {
    name                           = "state-blob"
    private_connection_resource_id = azurerm_storage_account.state.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}
