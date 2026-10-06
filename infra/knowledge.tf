resource "azurerm_search_service" "knowledge" {
  name                = "srch-${local.resource_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.search_sku
  replica_count       = 1
  partition_count     = 1
  semantic_search_sku = "standard"
  tags                = local.tags

  # The project identity authenticates to Search; ontology queries also need a user token.
  local_authentication_enabled = true
  authentication_failure_mode  = "http401WithBearerChallenge"

  identity {
    type = "SystemAssigned"
  }
}

data "fabric_lakehouse" "knowledge" {
  count = var.knowledge_lakehouse_id == null ? 0 : 1

  id           = var.knowledge_lakehouse_id
  workspace_id = fabric_workspace.dev.id
}

data "fabric_ontology" "knowledge" {
  for_each = var.knowledge_ontologies

  id           = each.value.ontology_id
  workspace_id = fabric_workspace.dev.id
}

# The OneLake indexer currently requires workspace Contributor, not Viewer.
resource "fabric_workspace_role_assignment" "search_onelake_contributor" {
  workspace_id = fabric_workspace.dev.id
  role         = "Contributor"
  principal = {
    id   = azurerm_search_service.knowledge.identity[0].principal_id
    type = "ServicePrincipal"
  }
}

resource "azurerm_role_assignment" "search_foundry_user" {
  scope                            = azapi_resource.foundry.id
  role_definition_name             = "Cognitive Services User"
  principal_id                     = azurerm_search_service.knowledge.identity[0].principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "project_search_reader" {
  scope                            = azurerm_search_service.knowledge.id
  role_definition_name             = "Search Index Data Reader"
  principal_id                     = azapi_resource.foundry_project.identity[0].principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "deployer_search_reader" {
  scope                = azurerm_search_service.knowledge.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "restful_resource" "knowledge_source" {
  count = var.knowledge_lakehouse_id == null ? 0 : 1

  path            = "/knowledgesources/${local.knowledge_source_name}"
  check_existance = true
  # Rebuild the generated ingestion objects when source settings change.
  force_new_attrs = ["name", "kind", "description", "indexedOneLakeParameters"]

  body = {
    name        = local.knowledge_source_name
    kind        = "indexedOneLake"
    description = "Documents from the ${var.project_name} DEV knowledge lakehouse Files area."
    indexedOneLakeParameters = {
      fabricWorkspaceId = fabric_workspace.dev.id
      lakehouseId       = data.fabric_lakehouse.knowledge[count.index].id
      ingestionParameters = {
        networkAccessMode         = "public"
        contentExtractionMode     = "minimal"
        disableImageVerbalization = true
        ingestionSchedule         = { interval = "PT5M" }
        embeddingModel = {
          kind = "azureOpenAI"
          azureOpenAIParameters = {
            resourceUri  = local.openai_endpoint
            deploymentId = azapi_resource.embedding_model.name
            modelName    = var.embedding_model.name
          }
        }
      }
    }
  }

  lifecycle {
    # Search redacts this ID on GET; changes are tracked by the workspace trigger.
    ignore_changes = [body.indexedOneLakeParameters.fabricWorkspaceId]
    replace_triggered_by = [
      azurerm_search_service.knowledge.id,
      fabric_workspace.dev.id,
      azapi_resource.embedding_model.body,
    ]
  }

  depends_on = [
    fabric_workspace_role_assignment.search_onelake_contributor,
    azurerm_role_assignment.search_foundry_user,
  ]
}

resource "restful_resource" "knowledge_base" {
  count = var.knowledge_lakehouse_id == null ? 0 : 1

  path            = "/knowledgebases/${local.knowledge_base_name}"
  check_existance = true

  body = {
    name                  = local.knowledge_base_name
    description           = "Foundry IQ knowledge base for ${var.project_name}."
    outputMode            = "answerSynthesis"
    answerInstructions    = "Answer using retrieved source results and include citations. If the sources do not contain the answer, say you do not know. Never report unavailable or unauthorized sources as successfully queried."
    retrievalInstructions = "Use connected Fabric ontology sources for current entities, relationships, statuses and counts. Use indexed OneLake files for documentation and background. Bootstrap documents are not live table data; do not substitute them for a failed ontology query."
    knowledgeSources = concat(
      [{ name = restful_resource.knowledge_source[count.index].body.name }],
      [for source in restful_resource.ontology_source : { name = source.body.name }],
    )
    models = [{
      kind = "azureOpenAI"
      azureOpenAIParameters = {
        resourceUri  = local.openai_endpoint
        deploymentId = azapi_resource.chat_model.name
        modelName    = var.chat_model.name
      }
    }]
    retrievalReasoningEffort = { kind = "low" }
  }

  lifecycle {
    # Search refuses to delete a source while a knowledge base references it.
    replace_triggered_by = [restful_resource.knowledge_source[count.index]]
  }
}

resource "restful_resource" "ontology_source" {
  for_each = var.knowledge_ontologies

  path            = "/knowledgesources/${var.project_name}-${each.key}-ontology"
  check_existance = true
  force_new_attrs = ["name", "kind"]

  body = {
    name        = "${var.project_name}-${each.key}-ontology"
    kind        = "fabricOntology"
    description = each.value.description
    fabricOntologyParameters = {
      workspaceId = fabric_workspace.dev.id
      ontologyId  = data.fabric_ontology.knowledge[each.key].id
    }
  }

  lifecycle {
    replace_triggered_by = [azurerm_search_service.knowledge.id]
  }
}
