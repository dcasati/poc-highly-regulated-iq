data "azurerm_client_config" "current" {}
data "azurerm_cognitive_account" "foundry" {
  name                = var.existing.foundry_name
  resource_group_name = var.existing.foundry_resource_group
}
data "azurerm_search_service" "existing" {
  name                = var.existing.search_name
  resource_group_name = var.existing.search_resource_group
}
data "azapi_resource" "search_properties" {
  type                   = "Microsoft.Search/searchServices@2025-05-01"
  resource_id            = data.azurerm_search_service.existing.id
  response_export_values = ["sku", "properties"]
}
data "azurerm_storage_account" "existing" {
  name                = var.existing.storage_name
  resource_group_name = var.existing.storage_resource_group
}
data "azurerm_virtual_network" "existing" {
  name                = var.existing.vnet_name
  resource_group_name = var.existing.network_resource_group
}
data "azurerm_subnet" "runtime" {
  name                 = var.existing.runtime_subnet_name
  virtual_network_name = var.existing.vnet_name
  resource_group_name  = var.existing.network_resource_group
}
data "azurerm_subnet" "endpoints" {
  name                 = var.existing.endpoint_subnet_name
  virtual_network_name = var.existing.vnet_name
  resource_group_name  = var.existing.network_resource_group
}
data "azurerm_private_dns_zone" "registry" {
  name                = "privatelink.azurecr.io"
  resource_group_name = var.existing.registry_dns_group
}
data "azapi_resource" "project" {
  type                   = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name                   = var.existing.project_name
  parent_id              = data.azurerm_cognitive_account.foundry.id
  response_export_values = ["identity.principalId"]
}

locals {
  suffix      = substr(sha256("${data.azurerm_client_config.current.subscription_id}/${var.project_name}"), 0, 8)
  prefix      = "${var.project_name}-${local.suffix}"
  tags        = merge(var.tags, { project = var.project_name, managed_by = "Terraform", scenario = "highly-regulated" })
  source_name = "${var.project_name}-review-source"
  base_name   = "${var.project_name}-review"
  index_name  = "${var.project_name}-evidence"
  containers  = { for name in ["originals", "review-state", "approved", "reviewed-evidence"] : name => "${var.project_name}-${name}" }
  image       = var.image_digest == null ? null : "${azurerm_container_registry.app.login_server}/review-portal@${var.image_digest}"
  portal_env = merge({
    Portal__TenantId                = var.identity.tenant_id
    Portal__ClientId                = var.identity.spa_client_id
    Portal__ApiAudience             = var.identity.api_client_id
    Portal__ApiScope                = var.identity.api_scope
    Portal__BlobEndpoint            = trimsuffix(data.azurerm_storage_account.existing.primary_blob_endpoint, "/")
    Portal__ContentEndpoint         = var.content_endpoint
    Portal__SearchEndpoint          = data.azurerm_search_service.existing.endpoint
    Portal__ProjectEndpoint         = var.project_endpoint
    Portal__AgentName               = var.existing.agent_name
    Portal__AnalyzerId              = var.analyzer_id
    Portal__KnowledgeBase           = local.base_name
    Portal__KnowledgeSource         = local.source_name
    Portal__OriginalContainer       = local.containers.originals
    Portal__StateContainer          = local.containers["review-state"]
    Portal__ApprovedContainer       = local.containers.approved
    Portal__EvidenceContainer       = local.containers["reviewed-evidence"]
    Portal__ProcessingLocation      = var.processing_location
    Portal__ConfidenceThreshold     = tostring(var.confidence_threshold)
    Portal__ManagedIdentityClientId = azurerm_user_assigned_identity.app.client_id
  }, { for i, field in sort(keys(var.analyzer_fields)) : "Portal__FieldNames__${i}" => field })
}

resource "terraform_data" "gates" {
  lifecycle {
    precondition {
      condition     = data.azurerm_client_config.current.tenant_id == var.identity.tenant_id
      error_message = "The active Azure directory must match the approved application directory."
    }
    precondition {
      condition     = data.azurerm_storage_account.existing.public_network_access == "Disabled" && !data.azurerm_search_service.existing.public_network_access_enabled && !data.azurerm_cognitive_account.foundry.public_network_access_enabled
      error_message = "This scenario requires private Storage, Search and Foundry; it will not change existing network settings."
    }
    precondition {
      condition     = contains(["standard", "standard2", "standard3"], data.azapi_resource.search_properties.output.sku.name)
      error_message = "Private indexing with Content Understanding requires Search S1 or higher, not the template's Basic tier."
    }
    precondition {
      condition     = try(data.azurerm_search_service.existing.identity[0].principal_id, null) != null
      error_message = "Existing Search must have a system-assigned identity for private Blob indexing and keyless skillset billing."
    }
    precondition {
      condition     = !var.deploy_runtime || (var.deploy_knowledge && var.compliance.approved && alltrue([for evidence in [var.compliance.platform_evidence, var.compliance.image_evidence, var.compliance.transport_evidence] : length(trimspace(evidence)) > 0]))
      error_message = "Do not deploy application containers before knowledge setup and reviewed platform, image and transport cryptographic evidence."
    }
  }
}

resource "azurerm_resource_group" "scenario" {
  name     = "rg-${local.prefix}"
  location = var.location
  tags     = local.tags
}
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${local.prefix}"
  resource_group_name = azurerm_resource_group.scenario.name
  location            = var.location
  tags                = local.tags
}
resource "azurerm_storage_container" "scenario" {
  for_each              = local.containers
  name                  = each.value
  storage_account_id    = data.azurerm_storage_account.existing.id
  container_access_type = "private"
  lifecycle { prevent_destroy = true }
  depends_on = [terraform_data.gates]
}
resource "azurerm_role_assignment" "app_storage" {
  for_each             = local.containers
  scope                = "${data.azurerm_storage_account.existing.id}/blobServices/default/containers/${each.value}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  depends_on           = [azurerm_storage_container.scenario]
}
resource "azurerm_role_assignment" "search_storage" {
  for_each = {
    for name, container in local.containers : name => container
    if contains(["approved", "reviewed-evidence"], name)
  }
  scope                = "${data.azurerm_storage_account.existing.id}/blobServices/default/containers/${each.value}"
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = try(data.azurerm_search_service.existing.identity[0].principal_id, null)
  depends_on           = [azurerm_storage_container.scenario, terraform_data.gates]
}
resource "azurerm_role_assignment" "app_search" {
  scope                = data.azurerm_search_service.existing.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}
resource "azurerm_role_assignment" "app_content" {
  scope                = data.azurerm_cognitive_account.foundry.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}
resource "azurerm_role_assignment" "app_project" {
  scope              = data.azapi_resource.project.id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id       = azurerm_user_assigned_identity.app.principal_id
}
resource "azurerm_container_registry" "app" {
  name                          = "acr${replace(var.project_name, "-", "")}${local.suffix}"
  resource_group_name           = azurerm_resource_group.scenario.name
  location                      = var.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false
  data_endpoint_enabled         = true
  tags                          = local.tags
}
resource "azurerm_private_endpoint" "registry" {
  name                = "pe-${local.prefix}-registry"
  resource_group_name = azurerm_resource_group.scenario.name
  location            = var.location
  subnet_id           = data.azurerm_subnet.endpoints.id
  private_service_connection {
    name                           = "registry"
    private_connection_resource_id = azurerm_container_registry.app.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "registry"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.registry.id]
  }
}
resource "azurerm_role_assignment" "app_pull" {
  scope                = azurerm_container_registry.app.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}
