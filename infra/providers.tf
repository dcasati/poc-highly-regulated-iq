# Azure providers use ARM_* environment variables or the active Azure CLI account.
provider "azapi" {}

provider "azurerm" {
  features {}

  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.CognitiveServices",
    "Microsoft.Fabric",
    "Microsoft.Search",
  ]
}

provider "fabric" {
  # Ontology metadata lookup is a preview feature in the pinned provider.
  preview = length(var.knowledge_ontologies) > 0
}

# AzAPI does not register Search knowledge-base/source data-plane resource types.
# Keep their CRUD lifecycle in Terraform; do not log this provider's HTTP traffic.
provider "restful" {
  base_url      = azurerm_search_service.knowledge.endpoint
  create_method = "PUT"
  update_method = "PUT"
  delete_method = "DELETE"
  header        = { Content-Type = "application/json" }
  query         = { api-version = [local.search_api_version] }

  security = {
    apikey = [{
      in    = "header"
      name  = "api-key"
      value = azurerm_search_service.knowledge.primary_key
    }]
  }

  client = {
    retry = {
      status_codes    = [429, 500, 502, 503, 504]
      count           = 6
      wait_in_sec     = 5
      max_wait_in_sec = 30
    }
  }
}