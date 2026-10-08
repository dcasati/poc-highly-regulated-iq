mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000001"
      tenant_id       = "00000000-0000-0000-0000-000000000002"
      object_id       = "00000000-0000-0000-0000-000000000003"
    }
  }
  mock_data "azurerm_virtual_network" {
    defaults = {
      name                = "vnet-unitpoc"
      id                  = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-unitpoc-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-unitpoc"
      resource_group_name = "rg-unitpoc-connectivity"
      location            = "westus3"
      address_space       = ["10.20.0.0/16"]
      tags                = { project = "unitpoc" }
    }
  }
  mock_data "azurerm_subnet" {
    defaults = {
      name             = "snet-unitpoc-private-endpoints"
      id               = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-unitpoc-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-unitpoc/subnets/snet-unitpoc-private-endpoints"
      address_prefixes = ["10.20.2.0/24"]
    }
  }
  mock_data "azurerm_private_dns_zone" {
    defaults = {
      id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-unitpoc-state/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      tags = { project = "unitpoc" }
    }
  }
}

mock_provider "azapi" {
  mock_data "azapi_resource" {
    defaults = { output = { tags = { project = "unitpoc" } } }
  }
  mock_resource "azapi_resource" {
    defaults = {
      output = {
        identity = { principalId = "00000000-0000-0000-0000-000000000004" }
        properties = {
          endpoints = { synthetic = "https://unitpoc.services.ai.azure.com" }
          status    = "Pending"
        }
      }
    }
  }
}

variables {
  project_name = "unitpoc"
  location     = "westus3"
  expected_context = {
    subscription_id = "00000000-0000-0000-0000-000000000001"
    tenant_id       = "00000000-0000-0000-0000-000000000002"
    object_id       = "00000000-0000-0000-0000-000000000003"
    principal_type  = "User"
  }
  network = {
    name                    = "vnet-unitpoc"
    resource_group_name     = "rg-unitpoc-connectivity"
    endpoint_subnet_name    = "snet-unitpoc-private-endpoints"
    blob_dns_resource_group = "rg-unitpoc-state"
  }
  capability_preview_approved = true
}

run "private_platform_only" {
  command = plan
  assert {
    condition     = length(azapi_resource.project) == 0 && length(azurerm_role_assignment.project_files) == 0
    error_message = "The first stage must not create a project or runtime bindings."
  }
  assert {
    condition = (alltrue([for account in azurerm_storage_account.foundation :
      account.public_network_access == "Disabled" && !account.shared_access_key_enabled &&
      !account.local_user_enabled && account.infrastructure_encryption_enabled
      ]) && !azurerm_search_service.foundation.public_network_access_enabled &&
      !azurerm_search_service.foundation.local_authentication_enabled &&
      !azurerm_cosmosdb_account.agent.public_network_access_enabled &&
    !azurerm_cosmosdb_account.agent.local_authentication_enabled)
    error_message = "All stores must remain private and keyless."
  }
  assert {
    condition = (azurerm_search_service.foundation.authentication_failure_mode == null &&
    azurerm_search_service.foundation.network_rule_bypass_option == "None")
    error_message = "Keyless Search must omit the incompatible authentication failure mode and retain no network bypass."
  }
  assert {
    condition = (azapi_resource.foundry.body.properties.publicNetworkAccess == "Disabled" &&
      azapi_resource.foundry.body.properties.disableLocalAuth &&
      azapi_resource.foundry.body.properties.networkInjections[0].scenario == "agent" &&
    !azapi_resource.foundry.body.properties.networkInjections[0].useMicrosoftManagedNetwork)
    error_message = "Private account networking and BYO injection must be configured at creation."
  }
  assert {
    condition = (azurerm_subnet.foundation["agent"].address_prefixes[0] == "10.20.0.0/24" &&
      azurerm_subnet.foundation["runtime"].address_prefixes[0] == "10.20.1.0/24" &&
      azurerm_subnet.foundation["build"].address_prefixes[0] == "10.20.4.0/24" &&
    length(azurerm_subnet.foundation["build"].delegation) == 0)
    error_message = "New subnet allocations must preserve the backend and router reservations."
  }
  assert {
    condition = (length(azurerm_private_endpoint.foundation) == 5 &&
      length(azurerm_private_dns_zone.foundation) == 6 &&
    !contains(values(local.dns_zones), "privatelink.blob.core.windows.net"))
    error_message = "Consume backend-owned Blob DNS and endpoint subnet rather than duplicate them."
  }
  assert {
    condition = alltrue([for deployment in azurerm_cognitive_deployment.model :
      deployment.sku[0].name == "DataZoneStandard" && deployment.sku[0].capacity == 10
    ]) && !output.readiness_gates.application_deployed && !output.readiness_gates.fips_certification_asserted
    error_message = "Use the approved model baseline and never assert application/FIPS readiness."
  }
}

run "reject_missing_preview_approval" {
  command = plan
  variables { capability_preview_approved = false }
  expect_failures = [terraform_data.gates]
}

run "reject_unverified_project" {
  command = plan
  variables { provision_project = true }
  expect_failures = [terraform_data.gates]
}

run "reject_foreign_identity" {
  command = plan
  variables {
    expected_context = {
      subscription_id = "00000000-0000-0000-0000-000000000001"
      tenant_id       = "00000000-0000-0000-0000-000000000002"
      object_id       = "00000000-0000-0000-0000-000000000099"
      principal_type  = "User"
    }
  }
  expect_failures = [terraform_data.gates]
}

run "reject_non_us_region" {
  command = plan
  variables { location = "swedencentral" }
  expect_failures = [var.location]
}

run "reject_global_model" {
  command = plan
  variables {
    models = {
      chat      = { name = "gpt-5.2", version = "2025-12-11", capacity = 10, sku = "GlobalStandard" }
      embedding = { name = "text-embedding-3-large", version = "1", capacity = 10, sku = "DataZoneStandard" }
    }
  }
  expect_failures = [var.models]
}

run "reject_runtime_without_project" {
  command = plan
  variables { configure_agent_runtime = true }
  expect_failures = [var.configure_agent_runtime]
}

run "reject_missing_runtime_bindings" {
  command = plan
  variables {
    provision_project             = true
    private_connectivity_verified = true
    configure_agent_runtime       = true
  }
  expect_failures = [var.agent_runtime]
}

run "project_after_private_verification" {
  command = plan
  variables {
    provision_project             = true
    private_connectivity_verified = true
  }
  assert {
    condition     = length(azapi_resource.project) == 1 && length(azurerm_role_assignment.project_files) == 0
    error_message = "Project provisioning must not silently grant undiscovered runtime data access."
  }
}

run "reject_unowned_dns" {
  command = plan
  override_data {
    target = data.azapi_resource.blob_dns_metadata
    values = { output = { tags = { project = "another-project" } } }
  }
  expect_failures = [terraform_data.gates]
}

run "deny_arbitrary_outbound" {
  command = plan
  assert {
    condition = alltrue([for group in azurerm_network_security_group.foundation :
      anytrue([for rule in group.security_rule :
        rule.name == "deny-other-egress" && rule.access == "Deny" &&
        rule.direction == "Outbound" && rule.destination_address_prefix == "*" &&
        rule.priority == 4096
        ]) && alltrue([for rule in group.security_rule :
        rule.access != "Allow" || !contains(["Internet", "*", "AzureCloud"], rule.destination_address_prefix)
      ])
    ])
    error_message = "Every reserved subnet must deny arbitrary egress without a broad public-cloud/internet exception."
  }
  assert {
    condition = alltrue([for group in azurerm_network_security_group.foundation :
      anytrue([for rule in group.security_rule :
        rule.name == "azure-dns" && rule.direction == "Outbound" &&
        rule.access == "Allow" && rule.destination_address_prefix == "168.63.129.16/32" &&
        rule.destination_port_range == "53"
        ]) && alltrue([for rule in group.security_rule :
        rule.destination_address_prefix != "AzurePlatformDNS" || rule.access == "Deny"
      ])
    ])
    error_message = "Azure DNS must use its fixed platform address; AzurePlatformDNS cannot be used in an Allow rule."
  }
}

run "runtime_role_shape_after_discovery" {
  command = plan
  variables {
    provision_project             = true
    private_connectivity_verified = true
    configure_agent_runtime       = true
    agent_runtime = {
      principal_ids          = ["00000000-0000-0000-0000-000000000004"]
      files_container        = "synthetic-files"
      intermediate_container = "synthetic-intermediate"
      database_name          = "synthetic_database"
      verification_reference = "synthetic mock binding, not cloud readiness"
    }
  }
  assert {
    condition = (
      length(azurerm_role_assignment.project_files) == 1 &&
      length(azurerm_role_assignment.project_intermediate) == 1 &&
      length(azurerm_cosmosdb_sql_role_assignment.project_data) == 1 &&
      length(azurerm_role_assignment.project_search) == 2 &&
      data.azapi_resource.agent_container["files"].name == "synthetic-files" &&
      data.azapi_resource.agent_database[0].name == "synthetic_database"
    )
    error_message = "Discovered bindings must produce the explicit scoped runtime role shape."
  }
}
