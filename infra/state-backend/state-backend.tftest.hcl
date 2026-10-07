mock_provider "azurerm" {
  mock_resource "azurerm_storage_account" {
    override_during = plan
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-testpoc-state/providers/Microsoft.Storage/storageAccounts/stteststate"
    }
  }
  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000001"
      tenant_id       = "00000000-0000-0000-0000-000000000002"
      object_id       = "00000000-0000-0000-0000-000000000003"
    }
  }
  mock_data "azurerm_virtual_network" {
    defaults = {
      id                  = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-testpoc-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-testpoc"
      name                = "vnet-testpoc"
      resource_group_name = "rg-testpoc-connectivity"
      location            = "westus3"
      address_space       = ["10.20.0.0/16"]
      tags                = { project = "testpoc" }
    }
  }
}

variables {
  project_name = "testpoc"
  location     = "westus3"
  connectivity_network = {
    name                = "vnet-testpoc"
    resource_group_name = "rg-testpoc-connectivity"
  }
  deployment_principal_type  = "User"
  backend_bootstrap_approved = true
}

run "private_keyless_backend" {
  command = plan

  assert {
    condition     = azurerm_storage_account.state.location == "westus3" && azurerm_storage_account.state.account_replication_type == "LRS"
    error_message = "The account and replicas must remain in the selected US region."
  }
  assert {
    condition     = azurerm_storage_account.state.public_network_access == "Disabled" && !azurerm_storage_account.state.shared_access_key_enabled && !azurerm_storage_account.state.allow_nested_items_to_be_public && azurerm_storage_account.state.default_to_oauth_authentication
    error_message = "Preserve private, keyless Entra authentication with no anonymous Blob access."
  }
  assert {
    condition     = azurerm_storage_account.state.https_traffic_only_enabled && azurerm_storage_account.state.min_tls_version == "TLS1_2" && azurerm_storage_account.state.infrastructure_encryption_enabled
    error_message = "Preserve transport and at-rest encryption without a compliance self-certification."
  }
  assert {
    condition     = azurerm_storage_account.state.network_rules[0].default_action == "Deny" && length(azurerm_storage_account.state.network_rules[0].bypass) == 1 && contains(azurerm_storage_account.state.network_rules[0].bypass, "None")
    error_message = "Do not add public-service firewall exceptions."
  }
  assert {
    condition     = azurerm_storage_account.state.blob_properties[0].versioning_enabled && azurerm_storage_account.state.blob_properties[0].delete_retention_policy[0].days == 30 && azurerm_storage_account.state.blob_properties[0].container_delete_retention_policy[0].days == 30
    error_message = "Preserve versioning and blob/container recovery protections."
  }
  assert {
    condition     = azurerm_storage_container.state.container_access_type == "private" && azurerm_role_assignment.deployment_state.role_definition_name == "Storage Blob Data Contributor" && azurerm_role_assignment.deployment_state.principal_id == data.azurerm_client_config.current.object_id
    error_message = "Grant only the existing deployment identity the declared state-container role."
  }
  assert {
    condition     = azurerm_role_assignment.deployment_state.scope == "${azurerm_storage_account.state.id}/blobServices/default/containers/tfstate"
    error_message = "The state role must be container-scoped, not account, resource-group or subscription-wide."
  }
  assert {
    condition     = azurerm_subnet.endpoints.address_prefixes[0] == "10.20.2.0/24" && !azurerm_subnet.endpoints.default_outbound_access_enabled && !azurerm_private_dns_zone_virtual_network_link.blob.registration_enabled
    error_message = "Use only the reserved PoC endpoint prefix and explicit private DNS link."
  }
  assert {
    condition     = output.backend_config.use_azuread_auth && output.backend_config.use_cli && length(distinct(values(output.suggested_state_keys))) == length(output.suggested_state_keys)
    error_message = "Native backend authentication must be keyless and root-specific keys must be distinct."
  }
}

run "bootstrap_approval_required" {
  command = plan
  variables {
    backend_bootstrap_approved = false
  }
  expect_failures = [terraform_data.approval]
}

run "non_us_region_rejected" {
  command = plan
  variables {
    location = "canadacentral"
  }
  expect_failures = [var.location]
}

run "network_region_mismatch_rejected" {
  command = plan
  variables {
    location = "westus2"
  }
  expect_failures = [terraform_data.approval]
}

run "unrelated_network_rejected" {
  command = plan
  variables {
    connectivity_network = {
      name                = "vnet-unrelated"
      resource_group_name = "rg-unrelated"
    }
  }
  expect_failures = [var.connectivity_network]
}
