mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000001"
      tenant_id       = "00000000-0000-0000-0000-000000000002"
      object_id       = "00000000-0000-0000-0000-000000000003"
    }
  }
  mock_data "azurerm_storage_account" {
    defaults = {
      id                    = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-unitpoc/providers/Microsoft.Storage/storageAccounts/stunitpoc"
      public_network_access = "Disabled"
      primary_blob_endpoint = "https://stunitpoc.blob.core.windows.net/"
    }
  }
  mock_data "azurerm_search_service" {
    defaults = {
      id                            = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-unitpoc/providers/Microsoft.Search/searchServices/srch-unitpoc"
      endpoint                      = "https://srch-unitpoc.search.windows.net"
      public_network_access_enabled = false
      identity                      = [{ type = "SystemAssigned", principal_id = "00000000-0000-0000-0000-000000000004" }]
    }
  }
  mock_data "azurerm_cognitive_account" {
    defaults = {
      id                            = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-unitpoc/providers/Microsoft.CognitiveServices/accounts/ai-unitpoc"
      public_network_access_enabled = false
    }
  }
  mock_data "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-unitpoc/providers/Microsoft.Network/virtualNetworks/vnet-unitpoc"
    }
  }
  mock_data "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-unitpoc/providers/Microsoft.Network/virtualNetworks/vnet-unitpoc/subnets/snet-unitpoc"
    }
  }
  mock_data "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-unitpoc/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
    }
  }
}
mock_provider "azapi" {
  mock_data "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-unitpoc/providers/Microsoft.CognitiveServices/accounts/ai-unitpoc/projects/unitpoc-review"
      output = {
        identity = { principalId = "00000000-0000-0000-0000-000000000005" }
        sku      = { name = "standard" }
      }
    }
  }
}
mock_provider "restful" {}
mock_provider "restful" {
  alias = "content"
}
mock_provider "kubernetes" {}

override_data {
  target = data.azapi_resource.blob_link
  values = {
    output = {
      properties = {
        status                = "Approved"
        groupId               = "blob"
        privateLinkResourceId = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-unitpoc/providers/Microsoft.Storage/storageAccounts/stunitpoc"
      }
    }
  }
}
override_data {
  target = data.azapi_resource.content_link["foundry_account"]
  values = {
    output = {
      properties = {
        status                = "Approved"
        groupId               = "foundry_account"
        privateLinkResourceId = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-unitpoc/providers/Microsoft.CognitiveServices/accounts/ai-unitpoc"
      }
    }
  }
}
override_data {
  target = data.azapi_resource.content_link["cognitiveservices_account"]
  values = {
    output = {
      properties = {
        status                = "Approved"
        groupId               = "cognitiveservices_account"
        privateLinkResourceId = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-unitpoc/providers/Microsoft.CognitiveServices/accounts/ai-unitpoc"
      }
    }
  }
}

variables {
  project_name = "unitpoc"
  location     = "westus3"
  existing = {
    foundry_name           = "ai-unitpoc"
    foundry_resource_group = "rg-unitpoc"
    project_name           = "unitpoc-review"
    agent_name             = "exempt-agent"
    search_name            = "srch-unitpoc"
    search_resource_group  = "rg-unitpoc"
    storage_name           = "stunitpoc"
    storage_resource_group = "rg-unitpoc"
    vnet_name              = "vnet-unitpoc"
    network_resource_group = "rg-unitpoc"
    runtime_subnet_name    = "snet-runtime"
    endpoint_subnet_name   = "snet-endpoints"
    registry_dns_group     = "rg-unitpoc"
    blob_shared_link_name  = "unitpoc-blob"
  }
  existing_content_links = {
    foundry_account           = "unitpoc-processing"
    cognitiveservices_account = "unitpoc-billing"
  }
  content_endpoint = "https://ai-unitpoc.services.ai.azure.com"
  project_endpoint = "https://ai-unitpoc.services.ai.azure.com/api/projects/unitpoc-review"
  analyzer_models = {
    completion = "gpt-5.2"
    embedding  = "text-embedding-3-large"
  }
  search_access_token  = "synthetic-test-token-not-a-credential"
  content_access_token = "synthetic-test-token-not-a-credential"
}

run "platform_without_browser_registrations" {
  command = plan
  assert {
    condition     = var.identity == null && length(local.portal_env) == 0 && length(azurerm_container_app.app) == 0 && length(azurerm_container_app_environment.app) == 0 && output.portal_url == null
    error_message = "Platform preparation must not require browser registrations or create an unauthenticated app."
  }
  assert {
    condition     = length(restful_resource.analyzer) == 0 && !azurerm_container_registry.app.admin_enabled && !azurerm_container_registry.app.public_network_access_enabled && azurerm_container_registry.app.network_rule_bypass_option == "None"
    error_message = "The initial platform must retain private/keyless ACR and defer analyzer deployment."
  }
  assert {
    condition = alltrue([for group, link in local.content_link_properties :
      link.status == "Approved" && link.groupId == group &&
    link.privateLinkResourceId == data.azurerm_cognitive_account.foundry.id])
    error_message = "Synthetic approved private-link fixtures must match their declared groups and targets."
  }
}

run "preserve_configured_browser_identity" {
  command = plan
  variables {
    identity = {
      tenant_id     = "00000000-0000-0000-0000-000000000002"
      spa_client_id = "00000000-0000-0000-0000-000000000006"
      api_client_id = "00000000-0000-0000-0000-000000000007"
      api_scope     = "api://00000000-0000-0000-0000-000000000007/access_as_user"
    }
  }
  assert {
    condition     = local.portal_env.Portal__TenantId == var.identity.tenant_id && local.portal_env.Portal__ApiScope == var.identity.api_scope
    error_message = "Configured runtime authentication values must remain unchanged."
  }
}

run "reject_foreign_directory" {
  command = plan
  variables {
    identity = {
      tenant_id     = "00000000-0000-0000-0000-000000000099"
      spa_client_id = "00000000-0000-0000-0000-000000000006"
      api_client_id = "00000000-0000-0000-0000-000000000007"
      api_scope     = "api://00000000-0000-0000-0000-000000000007/access_as_user"
    }
  }
  expect_failures = [terraform_data.gates]
}

run "reject_runtime_without_browser_identity" {
  command = plan
  variables {
    deploy_runtime    = true
    provision_hosting = true
    deploy_knowledge  = true
    image_digest      = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    compliance = {
      approved           = true
      platform_evidence  = "synthetic-test-platform-reference"
      image_evidence     = "synthetic-test-image-reference"
      transport_evidence = "synthetic-test-transport-reference"
    }
  }
  expect_failures = [var.identity]
}

run "reject_runtime_without_crypto_approval" {
  command = plan
  variables {
    identity = {
      tenant_id     = "00000000-0000-0000-0000-000000000002"
      spa_client_id = "00000000-0000-0000-0000-000000000006"
      api_client_id = "00000000-0000-0000-0000-000000000007"
      api_scope     = "api://00000000-0000-0000-0000-000000000007/access_as_user"
    }
    deploy_runtime    = true
    provision_hosting = true
    deploy_knowledge  = true
    image_digest      = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [terraform_data.gates]
}

run "reject_runtime_without_hosting" {
  command = plan
  variables {
    identity = {
      tenant_id     = "00000000-0000-0000-0000-000000000002"
      spa_client_id = "00000000-0000-0000-0000-000000000006"
      api_client_id = "00000000-0000-0000-0000-000000000007"
      api_scope     = "api://00000000-0000-0000-0000-000000000007/access_as_user"
    }
    deploy_runtime   = true
    deploy_knowledge = true
    image_digest     = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    compliance = {
      approved           = true
      platform_evidence  = "synthetic-test-platform-reference"
      image_evidence     = "synthetic-test-image-reference"
      transport_evidence = "synthetic-test-transport-reference"
    }
  }
  expect_failures = [terraform_data.gates]
}

run "reviewed_hosting_without_runtime" {
  command = plan
  variables { provision_hosting = true }
  assert {
    condition     = length(azurerm_container_app_environment.app) == 1 && length(azurerm_container_app.app) == 0 && output.portal_url == null
    error_message = "The reviewed hosting stage must not deploy an application or advertise an uncreated portal."
  }
}

run "reject_mismatched_api_scope" {
  command = plan
  variables {
    identity = {
      tenant_id     = "00000000-0000-0000-0000-000000000002"
      spa_client_id = "00000000-0000-0000-0000-000000000006"
      api_client_id = "00000000-0000-0000-0000-000000000007"
      api_scope     = "api://00000000-0000-0000-0000-000000000099/access_as_user"
    }
  }
  expect_failures = [var.identity]
}

run "reject_malformed_application_guid" {
  command = plan
  variables {
    identity = {
      tenant_id     = "00000000-0000-0000-0000-000000000002"
      spa_client_id = "------------------------------------"
      api_client_id = "00000000-0000-0000-0000-000000000007"
      api_scope     = "api://00000000-0000-0000-0000-000000000007/access_as_user"
    }
  }
  expect_failures = [var.identity]
}
