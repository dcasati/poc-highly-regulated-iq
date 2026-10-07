output "backend_config" {
  description = "Nonsensitive native azurerm backend settings. Add a distinct root-specific key in ignored local configuration after migration approval."
  value = {
    resource_group_name  = azurerm_resource_group.state.name
    storage_account_name = azurerm_storage_account.state.name
    container_name       = azurerm_storage_container.state.name
    use_azuread_auth     = true
    use_cli              = true
  }
}

output "blob_hostname" {
  description = "Exact PoC Blob hostname for scoped split DNS through the US router; do not override an unrelated project's service domains."
  value       = trimsuffix(trimprefix(azurerm_storage_account.state.primary_blob_endpoint, "https://"), "/")
}

output "endpoint_subnet" {
  description = "New PoC endpoint subnet, owned by this root. Future foundation roots must read it, not recreate or import it."
  value = {
    id                  = azurerm_subnet.endpoints.id
    name                = azurerm_subnet.endpoints.name
    resource_group_name = azurerm_subnet.endpoints.resource_group_name
    vnet_name           = azurerm_subnet.endpoints.virtual_network_name
    address_prefixes    = azurerm_subnet.endpoints.address_prefixes
  }
}

output "blob_private_dns_zone" {
  description = "PoC-owned Blob private DNS zone for separately reviewed future PoC endpoints."
  value = {
    id                  = azurerm_private_dns_zone.blob.id
    name                = azurerm_private_dns_zone.blob.name
    resource_group_name = azurerm_private_dns_zone.blob.resource_group_name
  }
}

output "suggested_state_keys" {
  description = "Distinct suggested Blob keys; no backend is initialized or state migrated by producing these outputs."
  value = {
    state_backend    = "state-backend/terraform.tfstate"
    connectivity     = "connectivity/terraform.tfstate"
    foundation       = "foundation/terraform.tfstate"
    highly_regulated = "highly-regulated/terraform.tfstate"
    acr_build        = "acr-build/terraform.tfstate"
  }
}
