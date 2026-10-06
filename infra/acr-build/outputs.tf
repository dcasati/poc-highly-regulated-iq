output "registry_name" {
  description = "Existing registry name for az acr build; no credentials are returned."
  value       = var.registry.name
}

output "registry_login_server" {
  description = "Existing private registry endpoint. Data-plane access still requires approved network connectivity."
  value       = data.azapi_resource.registry.output.properties.loginServer
}

output "agent_pool_name" {
  description = "New pool name to pass explicitly to az acr build --agent-pool."
  value       = azurerm_container_registry_agent_pool.build.name
}

output "agent_pool_id" {
  description = "Scenario-owned pool resource ID, not ownership of the existing registry or subnet."
  value       = azurerm_container_registry_agent_pool.build.id
}

output "instance_count" {
  description = "Allocated pool instances. Zero disables build execution; a successful apply is not a connectivity or FIPS check."
  value       = azurerm_container_registry_agent_pool.build.instance_count
}
