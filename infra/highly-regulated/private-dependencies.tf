data "azapi_resource" "blob_link" {
  type                   = "Microsoft.Search/searchServices/sharedPrivateLinkResources@2025-05-01"
  name                   = var.existing.blob_shared_link_name
  parent_id              = data.azurerm_search_service.existing.id
  response_export_values = ["properties"]
}
data "azapi_resource" "content_link" {
  for_each               = var.existing_content_links
  type                   = "Microsoft.Search/searchServices/sharedPrivateLinkResources@2025-05-01"
  name                   = each.value
  parent_id              = data.azurerm_search_service.existing.id
  response_export_values = ["properties"]
}
resource "azapi_resource" "content_link" {
  for_each  = setsubtract(toset(["foundry_account", "cognitiveservices_account"]), toset(keys(var.existing_content_links)))
  type      = "Microsoft.Search/searchServices/sharedPrivateLinkResources@2025-05-01"
  name      = "${var.project_name}-${replace(each.key, "_", "-")}"
  parent_id = data.azurerm_search_service.existing.id
  locks     = [data.azurerm_search_service.existing.id]
  body = {
    properties = {
      groupId               = each.key
      privateLinkResourceId = data.azurerm_cognitive_account.foundry.id
      requestMessage        = "Review and approve private Content Understanding ${each.key} dependency."
    }
  }
  response_export_values = ["properties"]
}
locals {
  content_link_properties = merge(
    { for group, link in data.azapi_resource.content_link : group => link.output.properties },
    { for group, link in azapi_resource.content_link : group => link.output.properties }
  )
}
resource "terraform_data" "private_dependencies" {
  lifecycle {
    precondition {
      condition = !var.deploy_knowledge || (
        data.azapi_resource.blob_link.output.properties.status == "Approved" &&
        data.azapi_resource.blob_link.output.properties.groupId == "blob" &&
        lower(data.azapi_resource.blob_link.output.properties.privateLinkResourceId) == lower(data.azurerm_storage_account.existing.id)
      )
      error_message = "The existing Search shared Blob link must be approved and point to the selected Storage account."
    }
    precondition {
      condition = !var.deploy_knowledge || alltrue([for group, link in local.content_link_properties :
        link.status == "Approved" && link.groupId == group &&
      lower(link.privateLinkResourceId) == lower(data.azurerm_cognitive_account.foundry.id)])
      error_message = "Content Understanding processing/billing shared private links require target-owner approval before knowledge deployment."
    }
  }
}
