output "foundry" {
  description = "Foundation account identity and provider-returned endpoints, not a readiness assertion."
  value = {
    name = azapi_resource.foundry.name, resource_group_name = azurerm_resource_group.foundation.name,
    id   = azapi_resource.foundry.id, endpoints = azapi_resource.foundry.output.properties.endpoints
  }
}

output "project" {
  description = "Selected actual project metadata after its separately approved stage; null before provisioning."
  value = var.provision_project ? {
    name         = azapi_resource.project[0].name, id = azapi_resource.project[0].id,
    principal_id = azapi_resource.project[0].output.identity.principalId,
    internal_id  = try(azapi_resource.project[0].output.properties.internalId, null),
    endpoints    = azapi_resource.project[0].output.properties.endpoints
  } : null
}

output "agent_capability" {
  description = "Native managed-agent host and provisioning state, not proof of a successful agent invocation."
  value = var.provision_agent_capability ? {
    id    = azapi_resource.agent_capability[0].id
    state = azapi_resource.agent_capability[0].output.properties.provisioningState
  } : null
}

output "scenario_existing" {
  description = "Foundation references for the scenario; add the verified prompt-agent name only after its separate bootstrap."
  value = {
    foundry_name           = azapi_resource.foundry.name
    foundry_resource_group = azurerm_resource_group.foundation.name
    search_name            = azurerm_search_service.foundation.name
    search_resource_group  = azurerm_resource_group.foundation.name
    storage_name           = azurerm_storage_account.foundation["application"].name
    storage_resource_group = azurerm_resource_group.foundation.name
    vnet_name              = data.azurerm_virtual_network.poc.name
    network_resource_group = data.azurerm_virtual_network.poc.resource_group_name
    runtime_subnet_name    = azurerm_subnet.foundation["runtime"].name
    endpoint_subnet_name   = data.azurerm_subnet.endpoints.name
    registry_dns_group     = azurerm_resource_group.foundation.name
    blob_shared_link_name  = azapi_resource.application_blob_link.name
    project_name           = var.provision_project ? azapi_resource.project[0].name : null
  }
}

output "build_subnet" {
  description = "Reserved build subnet; package/platform egress and ACR pool preview approval are still required."
  value = {
    name                 = azurerm_subnet.foundation["build"].name,
    virtual_network_name = data.azurerm_virtual_network.poc.name,
    resource_group_name  = data.azurerm_virtual_network.poc.resource_group_name
  }
}

output "model_deployments" {
  description = "Model defaults mapping inputs; not proof that Content Understanding supports the analyzer."
  value       = { for name, deployment in azurerm_cognitive_deployment.model : name => deployment.name }
}

output "agent_stores" {
  description = "Only this foundation's agent-store identities for native runtime-binding discovery; no credentials or application/state access."
  value = {
    resource_group_name = azurerm_resource_group.foundation.name
    blob_name           = azurerm_storage_account.foundation["agent"].name
    blob_id             = azurerm_storage_account.foundation["agent"].id
    cosmos_name         = azurerm_cosmosdb_account.agent.name
    cosmos_id           = azurerm_cosmosdb_account.agent.id
  }
}

output "blob_shared_link_status" {
  description = "Native Search-to-application-Blob request status; target-owner approval is separate."
  value       = azapi_resource.application_blob_link.output.properties.status
}

output "private_endpoint_addresses" {
  description = "Provider-returned addresses for exact-hostname OS DNS/HTTPS verification."
  value       = { for name, endpoint in azurerm_private_endpoint.foundation : name => endpoint.private_service_connection[0].private_ip_address }
}

output "readiness_gates" {
  description = "Configured stage gates only; no indexing, agent, application or FIPS readiness claim."
  value = {
    project_stage_enabled       = var.provision_project
    provisioning_roles_enabled  = var.configure_agent_provisioning
    capability_stage_enabled    = var.provision_agent_capability
    runtime_roles_enabled       = var.configure_agent_runtime
    operator_private_verified   = var.private_connectivity_verified
    application_deployed        = false
    fips_certification_asserted = false
  }
}
