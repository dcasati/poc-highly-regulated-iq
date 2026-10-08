output "portal_identity" {
  description = "Discovered real application IDs for the scenario identity input; not proof of browser login, redirect routing or cryptographic readiness."
  value = {
    tenant_id     = data.azuread_client_config.current.tenant_id
    api_client_id = azuread_application.api.client_id
    spa_client_id = azuread_application.spa.client_id
    api_scope     = "api://${azuread_application.api.client_id}/access_as_user"
  }
}
