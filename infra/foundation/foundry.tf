resource "azurerm_role_assignment" "caller_agent_blob" {
  scope                = azurerm_storage_account.foundation["agent"].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = var.expected_context.principal_type
}

resource "azurerm_role_assignment" "caller_cosmos" {
  scope                = azurerm_cosmosdb_account.agent.id
  role_definition_name = "Cosmos DB Operator"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = var.expected_context.principal_type
}

resource "azapi_resource" "foundry" {
  type                      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name                      = "ai-${local.prefix}"
  parent_id                 = azurerm_resource_group.foundation.id
  location                  = var.location
  tags                      = local.tags
  schema_validation_enabled = false
  identity {
    type = "SystemAssigned"
  }
  body = {
    kind = "AIServices"
    sku  = { name = "S0" }
    properties = {
      allowProjectManagement        = true
      customSubDomainName           = "ai-${local.prefix}"
      publicNetworkAccess           = "Disabled"
      disableLocalAuth              = true
      restrictOutboundNetworkAccess = true
      networkAcls                   = { defaultAction = "Deny", bypass = "None", ipRules = [], virtualNetworkRules = [] }
      networkInjections = [{
        scenario                   = "agent"
        subnetArmId                = azurerm_subnet.foundation["agent"].id
        useMicrosoftManagedNetwork = false
      }]
    }
  }
  response_export_values = ["identity.principalId", "properties.endpoints"]
  lifecycle { prevent_destroy = true }
  depends_on = [
    azurerm_role_assignment.caller_agent_blob, azurerm_role_assignment.caller_cosmos,
    azurerm_subnet_network_security_group_association.foundation,
    azurerm_private_dns_zone_virtual_network_link.foundation
  ]
}

resource "azapi_resource" "chat_prompt_shields" {
  type                      = "Microsoft.CognitiveServices/accounts/raiPolicies@2025-06-01"
  name                      = "chat-prompt-shields"
  parent_id                 = azapi_resource.foundry.id
  schema_validation_enabled = true
  # Preserve service-added filters while detecting drift in each owned name/source pair.
  ignore_other_items_in_list = ["properties.contentFilters"]
  list_unique_id_property    = { "properties.contentFilters" = "name,source" }
  body = {
    properties = {
      basePolicyName = "Microsoft.Default"
      mode           = "Blocking"
      contentFilters = concat(
        flatten([for category in ["Hate", "Sexual", "Violence", "Selfharm"] : [
          for source in ["Prompt", "Completion"] : {
            name              = category
            source            = source
            enabled           = true
            blocking          = true
            severityThreshold = "Medium"
          }
        ]]),
        [
          for detector in ["Jailbreak", "Indirect Attack"] : {
            name     = detector
            source   = "Prompt"
            enabled  = true
            blocking = true
          }
        ],
        [
          for detector in ["Protected Material Text", "Protected Material Code"] : {
            name     = detector
            source   = "Completion"
            enabled  = true
            blocking = true
          }
        ]
      )
    }
  }
  # The API catalog's policy filter name is "Indirect Attack", not its ARM ID "IndirectAttack".
  # Document detection requires JSON-escaped """ <documents> ... </documents> """ context.
  # Microsoft's document-format contract describes Chat Completions, not Responses:
  # https://learn.microsoft.com/azure/ai-foundry/openai/concepts/content-filter-document-embedding
  lifecycle { prevent_destroy = true }
}

resource "azurerm_cognitive_deployment" "model" {
  for_each               = { chat = var.models.chat, embedding = var.models.embedding }
  name                   = each.key
  cognitive_account_id   = azapi_resource.foundry.id
  rai_policy_name        = each.key == "chat" ? azapi_resource.chat_prompt_shields.name : null
  version_upgrade_option = "NoAutoUpgrade"
  model {
    format  = "OpenAI"
    name    = each.value.name
    version = each.value.version
  }
  sku {
    name     = each.value.sku
    capacity = each.value.capacity
  }
  lifecycle { prevent_destroy = true }
}

resource "azurerm_role_assignment" "caller_search" {
  for_each             = toset(["Search Service Contributor", "Search Index Data Contributor"])
  scope                = azurerm_search_service.foundation.id
  role_definition_name = each.value
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = var.expected_context.principal_type
}

resource "azurerm_role_assignment" "caller_content" {
  scope                = azapi_resource.foundry.id
  role_definition_name = "Cognitive Services User"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = var.expected_context.principal_type
}

resource "azurerm_role_assignment" "foundry_models" {
  scope                = azapi_resource.foundry.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azapi_resource.foundry.output.identity.principalId
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "search_content" {
  scope                = azapi_resource.foundry.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_search_service.foundation.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
