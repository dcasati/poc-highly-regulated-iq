resource "azurerm_storage_account" "foundation" {
  for_each                          = { application = "app", agent = "agt" }
  name                              = "st${local.storage_key}${each.value}${local.suffix}"
  resource_group_name               = azurerm_resource_group.foundation.name
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

resource "azurerm_cosmosdb_account" "agent" {
  name                                  = "cosmos-${local.prefix}"
  resource_group_name                   = azurerm_resource_group.foundation.name
  location                              = var.location
  offer_type                            = "Standard"
  kind                                  = "GlobalDocumentDB"
  public_network_access_enabled         = false
  local_authentication_enabled          = false
  network_acl_bypass_for_azure_services = false
  minimal_tls_version                   = "Tls12"
  consistency_policy {
    consistency_level = "Session"
  }
  capabilities {
    name = "EnableServerless"
  }
  geo_location {
    location          = var.location
    failover_priority = 0
  }
  tags = local.tags
  lifecycle { prevent_destroy = true }
}

resource "azurerm_search_service" "foundation" {
  name                          = "srch-${local.prefix}"
  resource_group_name           = azurerm_resource_group.foundation.name
  location                      = var.location
  sku                           = "standard"
  replica_count                 = 1
  partition_count               = 1
  public_network_access_enabled = false
  local_authentication_enabled  = false
  authentication_failure_mode   = "http403"
  network_rule_bypass_option    = "None"
  semantic_search_sku           = "standard"
  identity {
    type = "SystemAssigned"
  }
  tags = local.tags
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "application_blob_link" {
  type      = "Microsoft.Search/searchServices/sharedPrivateLinkResources@2025-05-01"
  name      = "${var.project_name}-application-blob"
  parent_id = azurerm_search_service.foundation.id
  body = {
    properties = {
      groupId               = "blob"
      privateLinkResourceId = azurerm_storage_account.foundation["application"].id
      requestMessage        = "Target-owner approval required for this PoC's private application indexing."
    }
  }
  response_export_values = ["properties"]
}
