resource "azapi_resource" "foundry" {
  type      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name      = "ai-${local.resource_prefix}"
  parent_id = azurerm_resource_group.main.id
  location  = azurerm_resource_group.main.location
  tags      = local.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku  = { name = "S0" }
    properties = {
      allowProjectManagement = true
      customSubDomainName    = "ai-${local.resource_prefix}"
      disableLocalAuth       = true
      publicNetworkAccess    = "Enabled"
    }
  }
}

resource "azapi_resource" "foundry_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = "${var.project_name}-project"
  parent_id = azapi_resource.foundry.id
  location  = azurerm_resource_group.main.location
  tags      = local.tags
  locks     = [azapi_resource.foundry.id]

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      displayName = "${var.project_name} project"
      description = "Fabric and Foundry IQ for ${var.project_name}."
    }
  }
}

resource "azapi_resource" "chat_model" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name      = "chat"
  parent_id = azapi_resource.foundry.id
  locks     = [azapi_resource.foundry.id]

  body = {
    sku = {
      name     = var.chat_model.sku
      capacity = var.chat_model.capacity
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = var.chat_model.name
        version = var.chat_model.version
      }
      versionUpgradeOption = "NoAutoUpgrade"
    }
  }
}

resource "azapi_resource" "embedding_model" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name      = "embedding"
  parent_id = azapi_resource.foundry.id
  locks     = [azapi_resource.foundry.id]

  body = {
    sku = {
      name     = var.embedding_model.sku
      capacity = var.embedding_model.capacity
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = var.embedding_model.name
        version = var.embedding_model.version
      }
      versionUpgradeOption = "NoAutoUpgrade"
    }
  }
}

# The published connection schema omits the documented connection properties.
resource "azapi_resource" "search_connection" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name                      = "knowledge-search"
  parent_id                 = azapi_resource.foundry_project.id
  schema_validation_enabled = false
  locks                     = [azapi_resource.foundry.id]

  body = {
    properties = {
      category      = "CognitiveSearch"
      authType      = "AAD"
      target        = azurerm_search_service.knowledge.endpoint
      isSharedToAll = false
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_search_service.knowledge.id
      }
    }
  }
}

# RemoteTool/ProjectManagedIdentity is documented but absent from AzAPI's schema.
resource "azapi_resource" "knowledge_base_connection" {
  count = var.knowledge_lakehouse_id == null ? 0 : 1

  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-10-01-preview"
  name                      = "knowledge-base"
  parent_id                 = azapi_resource.foundry_project.id
  schema_validation_enabled = false
  locks                     = [azapi_resource.foundry.id]

  body = {
    properties = {
      category      = "RemoteTool"
      authType      = "ProjectManagedIdentity"
      target        = local.knowledge_base_mcp_endpoint
      audience      = "https://search.azure.com/"
      isSharedToAll = false
      metadata      = { ApiType = "Azure" }
    }
  }

  depends_on = [azurerm_role_assignment.project_search_reader]
}

resource "azurerm_role_assignment" "deployer_foundry_user" {
  scope        = azapi_resource.foundry.id
  principal_id = data.azurerm_client_config.current.object_id

  # Foundry User, formerly Azure AI User; the role ID survives the rename.
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
}
