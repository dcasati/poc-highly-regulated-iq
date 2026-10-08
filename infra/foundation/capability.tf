locals {
  agent_connections = var.configure_agent_provisioning ? {
    blob = {
      name   = azurerm_storage_account.foundation["agent"].name, category = "AzureStorageAccount"
      target = azurerm_storage_account.foundation["agent"].primary_blob_endpoint
      metadata = {
        ApiType = "Azure", ResourceId = azurerm_storage_account.foundation["agent"].id, location = var.location
      }
    }
    cosmos = {
      name   = azurerm_cosmosdb_account.agent.name, category = "CosmosDb"
      target = azurerm_cosmosdb_account.agent.endpoint
      metadata = {
        ApiType = "Azure", ResourceId = azurerm_cosmosdb_account.agent.id, location = var.location
      }
    }
    search = {
      name   = azurerm_search_service.foundation.name, category = "CognitiveSearch"
      target = "https://${azurerm_search_service.foundation.name}.search.windows.net"
      metadata = {
        ApiType    = "Azure", ApiVersion = "2025-05-01-preview"
        ResourceId = azurerm_search_service.foundation.id, location = var.location
      }
    }
  } : {}
  provisioning_search_roles = var.configure_agent_provisioning ? {
    for role in ["Search Index Data Contributor", "Search Service Contributor"] :
    "provisioning/${role}" => { principal = lower(var.agent_provisioning.principal_id), role = role }
  } : {}
}

resource "terraform_data" "provisioning_bindings" {
  count = var.configure_agent_provisioning ? 1 : 0
  lifecycle {
    precondition {
      condition     = lower(var.agent_provisioning.principal_id) == lower(azapi_resource.project[0].output.identity.principalId)
      error_message = "Provisioning grants must target the actual project system identity, not another principal."
    }
  }
}

resource "azapi_resource" "agent_connection" {
  for_each                  = local.agent_connections
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name                      = each.value.name
  parent_id                 = azapi_resource.project[0].id
  schema_validation_enabled = false
  body = {
    properties = {
      category = each.value.category, target = each.value.target
      authType = "AAD", isSharedToAll = false, metadata = each.value.metadata
    }
  }
  response_export_values = ["properties.category", "properties.authType", "properties.target", "properties.metadata"]
  lifecycle { prevent_destroy = true }
  depends_on = [terraform_data.provisioning_bindings]
}

resource "azurerm_role_assignment" "project_provisioning" {
  for_each = var.configure_agent_provisioning ? merge({
    cosmos = { scope = azurerm_cosmosdb_account.agent.id, role = "Cosmos DB Operator" }
    }, var.configure_agent_runtime ? {} : {
    blob = { scope = azurerm_storage_account.foundation["agent"].id, role = "Storage Blob Data Contributor" }
  }) : {}
  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = var.agent_provisioning.principal_id
  principal_type       = "ServicePrincipal"
  depends_on           = [terraform_data.provisioning_bindings]
}

resource "azurerm_role_assignment" "project_provisioning_search" {
  for_each             = local.provisioning_search_roles
  scope                = azurerm_search_service.foundation.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal
  principal_type       = "ServicePrincipal"
  depends_on           = [terraform_data.provisioning_bindings]
}

resource "azapi_resource" "agent_capability" {
  count                     = var.provision_agent_capability ? 1 : 0
  type                      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name                      = "agents"
  parent_id                 = azapi_resource.project[0].id
  schema_validation_enabled = false
  body = {
    properties = {
      capabilityHostKind       = "Agents"
      vectorStoreConnections   = [azapi_resource.agent_connection["search"].name]
      storageConnections       = [azapi_resource.agent_connection["blob"].name]
      threadStorageConnections = [azapi_resource.agent_connection["cosmos"].name]
    }
  }
  response_export_values = ["properties.provisioningState"]
  timeouts { create = "30m" }
  lifecycle { prevent_destroy = true }
  depends_on = [
    terraform_data.gates, azurerm_role_assignment.project_provisioning,
    azurerm_role_assignment.project_provisioning_search
  ]
}
