resource "azapi_resource" "project" {
  count                     = var.provision_project ? 1 : 0
  type                      = "Microsoft.CognitiveServices/accounts/projects@2026-07-15-preview"
  name                      = "${var.project_name}-review"
  parent_id                 = azapi_resource.foundry.id
  location                  = var.location
  tags                      = local.tags
  schema_validation_enabled = false
  identity {
    type = "SystemAssigned"
  }
  body = {
    properties = {
      displayName = "${var.project_name} document review"
      description = "Synthetic-only private document review; no production or FIPS readiness claim."
    }
  }
  response_export_values = ["identity.principalId", "properties"]
  lifecycle { prevent_destroy = true }
  depends_on = [terraform_data.gates, azurerm_private_endpoint.foundation, azurerm_cognitive_deployment.model]
}

resource "azurerm_role_assignment" "caller_project" {
  count              = var.provision_project ? 1 : 0
  scope              = azapi_resource.project[0].id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id       = data.azurerm_client_config.current.object_id
  principal_type     = var.expected_context.principal_type
}

resource "terraform_data" "runtime_bindings" {
  count = var.configure_agent_runtime ? 1 : 0
  lifecycle {
    precondition {
      condition     = contains(local.runtime_principals, lower(azapi_resource.project[0].output.identity.principalId))
      error_message = "Verified runtime identities must include the actual project system-assigned identity."
    }
  }
}

data "azapi_resource" "agent_container" {
  for_each = var.configure_agent_runtime ? {
    files = var.agent_runtime.files_container, intermediate = var.agent_runtime.intermediate_container
  } : {}
  type                   = "Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01"
  name                   = each.value
  parent_id              = "${azurerm_storage_account.foundation["agent"].id}/blobServices/default"
  response_export_values = ["name"]
}

data "azapi_resource" "agent_database" {
  count                  = var.configure_agent_runtime ? 1 : 0
  type                   = "Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2025-04-15"
  name                   = var.agent_runtime.database_name
  parent_id              = azurerm_cosmosdb_account.agent.id
  response_export_values = ["name"]
}

locals {
  runtime_principals = var.configure_agent_runtime ? toset([for id in var.agent_runtime.principal_ids : lower(id)]) : toset([])
  runtime_roles = {
    for binding in setproduct(local.runtime_principals, [
      "Search Index Data Contributor", "Search Service Contributor"
    ]) : "${binding[0]}/${binding[1]}" => { principal = binding[0], role = binding[1] }
  }
}

resource "azurerm_role_assignment" "project_store_control" {
  for_each = var.configure_agent_runtime ? {
    blob   = { scope = azurerm_storage_account.foundation["agent"].id, role = "Storage Account Contributor" }
    cosmos = { scope = azurerm_cosmosdb_account.agent.id, role = "Cosmos DB Operator" }
  } : {}
  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azapi_resource.project[0].output.identity.principalId
  principal_type       = "ServicePrincipal"
  depends_on           = [terraform_data.runtime_bindings]
}

resource "azurerm_role_assignment" "project_search" {
  for_each             = local.runtime_roles
  scope                = azurerm_search_service.foundation.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal
  principal_type       = "ServicePrincipal"
  depends_on           = [terraform_data.runtime_bindings]
}

resource "azurerm_role_assignment" "project_models" {
  for_each             = local.runtime_principals
  scope                = azapi_resource.foundry.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
  depends_on           = [terraform_data.runtime_bindings]
}

resource "azurerm_role_assignment" "project_files" {
  for_each             = local.runtime_principals
  scope                = data.azapi_resource.agent_container["files"].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
  depends_on           = [terraform_data.runtime_bindings]
}

resource "azurerm_role_assignment" "project_intermediate" {
  for_each             = local.runtime_principals
  scope                = data.azapi_resource.agent_container["intermediate"].id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
  depends_on           = [terraform_data.runtime_bindings]
}

resource "azurerm_cosmosdb_sql_role_assignment" "project_data" {
  for_each            = local.runtime_principals
  resource_group_name = azurerm_resource_group.foundation.name
  account_name        = azurerm_cosmosdb_account.agent.name
  role_definition_id  = "${azurerm_cosmosdb_account.agent.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  scope               = "${azurerm_cosmosdb_account.agent.id}/dbs/${data.azapi_resource.agent_database[0].name}"
  principal_id        = each.value
  depends_on          = [terraform_data.runtime_bindings]
}
