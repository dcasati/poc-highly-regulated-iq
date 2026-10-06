output "resource_group_name" {
  description = "Resource group containing the Azure infrastructure."
  value       = azurerm_resource_group.main.name
}

output "fabric_capacity_id" {
  description = "Fabric capacity GUID used by both workspaces."
  value       = data.fabric_capacity.capacity.id
}

output "fabric_capacity_resource_id" {
  description = "Azure resource ID of the newly provisioned capacity."
  value       = azurerm_fabric_capacity.main.id
}

output "dev_workspace_id" {
  description = "DEV workspace GUID; connect and sync Git with the Bootstrap deployment plan after platform setup."
  value       = fabric_workspace.dev.id
}

output "dev_workspace_name" {
  description = "Display name of the DEV bootstrap target."
  value       = fabric_workspace.dev.display_name
}

output "test_workspace_id" {
  description = "Initially empty TEST workspace."
  value       = fabric_workspace.test.id
}

output "test_workspace_name" {
  description = "Display name of the TEST item-promotion target."
  value       = fabric_workspace.test.display_name
}

output "github_repository_url" {
  description = "Repository to connect to the DEV workspace."
  value       = local.github_repository_url
}

output "github_connection_id" {
  description = "GitHub credentials connection for plan-driven DEV Git bootstrap; not a PAT."
  value       = fabric_connection.github.id
}

output "github_connect_request" {
  description = "Fabric Git Connect API request body. Terraform does not connect, initialize or synchronize Git."
  value = {
    gitProviderDetails = {
      gitProviderType = "GitHub"
      ownerName       = lower(var.github_owner)
      repositoryName  = var.github_repository_name
      branchName      = var.github_branch_name
      directoryName   = var.github_directory_name
    }
    myGitCredentials = {
      source       = "ConfiguredConnection"
      connectionId = fabric_connection.github.id
    }
  }
}

output "deployment_pipeline_id" {
  description = "Native Fabric DEV/TEST deployment pipeline; no content is deployed by Terraform."
  value       = fabric_deployment_pipeline.main.id
}

output "deployment_pipeline_stage_ids" {
  description = "Native Fabric stage GUIDs keyed by stage name."
  value       = { for stage in fabric_deployment_pipeline.main.stages : stage.display_name => stage.id }
}

output "foundry_project_endpoint" {
  description = "Foundry project API endpoint."
  value       = "https://${azapi_resource.foundry.name}.services.ai.azure.com/api/projects/${azapi_resource.foundry_project.name}"
}

output "foundry_project_id" {
  description = "Foundry project Azure resource ID."
  value       = azapi_resource.foundry_project.id
}

output "model_deployments" {
  description = "Foundry model deployment names."
  value = {
    chat      = azapi_resource.chat_model.name
    embedding = azapi_resource.embedding_model.name
  }
}

output "search_endpoint" {
  description = "Azure AI Search endpoint."
  value       = azurerm_search_service.knowledge.endpoint
}

output "knowledge_base_name" {
  description = "Foundry IQ knowledge base, backed by Azure AI Search; absent until knowledge setup."
  value       = one(restful_resource.knowledge_base[*].body.name)
}

output "knowledge_setup_pending" {
  description = "True until the Git-created DEV lakehouse GUID is supplied. False does not imply asynchronous ingestion has finished."
  value       = var.knowledge_lakehouse_id == null
}

output "knowledge_source_status_url" {
  description = "GET with a Search token to inspect asynchronous ingestion and errors."
  value       = var.knowledge_lakehouse_id == null ? null : "${azurerm_search_service.knowledge.endpoint}/knowledgesources/${restful_resource.knowledge_source[0].body.name}/status?api-version=${local.search_api_version}"
}

output "knowledge_base_mcp_endpoint" {
  description = "Knowledge-base MCP endpoint for Foundry agents."
  value       = local.knowledge_base_mcp_endpoint
}

output "knowledge_base_connection_id" {
  description = "Project connection resource ID for the knowledge-base MCP tool."
  value       = one(azapi_resource.knowledge_base_connection[*].id)
}

output "knowledge_lakehouse_id" {
  description = "Git-owned DEV lakehouse containing the knowledge source files; absent until knowledge setup."
  value       = one(data.fabric_lakehouse.knowledge[*].id)
}

output "knowledge_lakehouse_name" {
  description = "Display name of the DEV knowledge lakehouse."
  value       = one(data.fabric_lakehouse.knowledge[*].display_name)
}

output "knowledge_files_url" {
  description = "Authenticated OneLake Files endpoint for source documents."
  value       = var.knowledge_lakehouse_id == null ? null : "https://onelake.dfs.fabric.microsoft.com/${fabric_workspace.dev.id}/${data.fabric_lakehouse.knowledge[0].id}/Files"
}

output "knowledge_source_name" {
  description = "Indexed OneLake source; use includeReferenceSourceData in retrieval requests for document URLs."
  value       = one(restful_resource.knowledge_source[*].body.name)
}

output "ontology_knowledge_sources" {
  description = "Live Fabric ontology sources registered in the knowledge base, with DEV physical item IDs. Empty until explicitly configured."
  value = {
    for name, source in restful_resource.ontology_source : name => {
      knowledge_source_name = source.body.name
      workspace_id          = fabric_workspace.dev.id
      ontology_id           = data.fabric_ontology.knowledge[name].id
    }
  }
}

output "knowledge_base_requires_user_token" {
  description = "When true, retrieval must include an end-user Search-audience token in x-ms-query-source-authorization. Project managed identity alone cannot query Fabric ontologies."
  value       = length(var.knowledge_ontologies) > 0
}