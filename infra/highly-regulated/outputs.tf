output "registry_login_server" {
  description = "Private ACR. Build and push from the approved VNet-connected build host."
  value       = azurerm_container_registry.app.login_server
}
output "registry_name" {
  description = "ACR name for Entra-authenticated login; admin credentials are disabled."
  value       = azurerm_container_registry.app.name
}
output "runtime_identity_client_id" {
  description = "Managed identity client ID, not a credential."
  value       = azurerm_user_assigned_identity.app.client_id
}
output "portal_url" {
  description = "Private UI URL; network, authentication, ingestion and cryptographic evidence still require live verification."
  value       = !var.provision_hosting || !var.deploy_runtime ? null : (var.hosting == "container_apps" ? "https://${azurerm_container_app.app[0].ingress[0].fqdn}" : "https://${var.aks.hostname}")
}
output "aks_cluster_name" {
  description = "Private AKS cluster when Container Apps is ruled out."
  value       = var.hosting == "aks" && var.provision_hosting ? azurerm_kubernetes_cluster.app[0].name : null
}
output "scenario_resource_group" {
  description = "Resource group owned by this scenario, separate from the existing AI infrastructure."
  value       = azurerm_resource_group.scenario.name
}
output "knowledge_base_mcp_endpoint" {
  description = "Operator connection target. Do not grant users unfiltered direct access to this service-wide endpoint."
  value       = var.deploy_knowledge ? "${data.azurerm_search_service.existing.endpoint}/knowledgebases/${local.base_name}/mcp?api-version=2026-08-01-preview" : null
}
output "indexer_status_urls" {
  description = "Inspect both execution histories, failures and actual indexed content before declaring readiness."
  value       = var.deploy_knowledge ? { for name in ["pdf", "fields"] : name => "${data.azurerm_search_service.existing.endpoint}/indexers/${local.index_name}-${name}/status?api-version=2026-08-01-preview" } : {}
}
output "content_private_link_status" {
  description = "Pending is not ready. Target owners must approve processing and billing links before the knowledge stage."
  value       = { for group, properties in local.content_link_properties : group => properties.status }
}
