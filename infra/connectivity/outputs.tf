output "resource_group_name" {
  description = "New PoC connectivity resource group, not another project's foundation."
  value       = azurerm_resource_group.connectivity.name
}

output "vm_name" {
  description = "Private router VM name for operator-controlled enrollment and status checks."
  value       = azurerm_linux_virtual_machine.router.name
}

output "vm_id" {
  description = "Private router VM resource ID."
  value       = azurerm_linux_virtual_machine.router.id
}

output "vm_private_ip" {
  description = "Azure private IP, not the separately assigned Tailscale IP."
  value       = azurerm_network_interface.router.private_ip_address
}

output "vnet" {
  description = "New US VNet identity for separately owned future PoC subnets; no inline subnets or unrelated imports."
  value = {
    id                  = azurerm_virtual_network.poc.id
    name                = azurerm_virtual_network.poc.name
    resource_group_name = azurerm_resource_group.connectivity.name
    location            = azurerm_virtual_network.poc.location
    address_space       = azurerm_virtual_network.poc.address_space
  }
}

output "nat_gateway_id" {
  description = "New PoC outbound gateway. Sharing it with future PoC subnets needs a reviewed plan."
  value       = azurerm_nat_gateway.egress.id
}

output "outbound_public_ip" {
  description = "NAT-only outbound IP; it does not permit Internet-initiated inbound connections to the VM."
  value       = azurerm_public_ip.egress.ip_address
}

output "future_endpoint_prefix" {
  description = "Reserved prefix for future US PoC private endpoints; this root does not create that subnet or any AI endpoints."
  value       = local.future_endpoint_prefix
}

output "tailscale_up_command" {
  description = "Operator-run enrollment command. Do not run automatically or add an auth key; approval is separate from Terraform apply."
  value       = "sudo tailscale up --hostname=${local.name} --accept-dns=false --advertise-routes=${local.future_endpoint_prefix} --timeout=45s"
}

output "split_dns_domains" {
  description = "Azure service suffixes for reference only, not approved DNS routes. Configure verified exact PoC service names and their private-link aliases instead; never override these broad suffixes in a shared tailnet."
  value = [
    "azurecr.io",
    "blob.core.windows.net",
    "search.windows.net",
    "services.ai.azure.com",
    "cognitiveservices.azure.com",
    "openai.azure.com",
    "azurecontainerapps.io"
  ]
}
