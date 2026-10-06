resource "azurerm_fabric_capacity" "main" {
  name                   = "fc${local.compact_prefix}${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  administration_members = var.fabric_capacity_admins
  tags                   = local.tags

  sku {
    name = var.fabric_capacity_sku
    tier = "Fabric"
  }
}

# Fabric workspace APIs require the Fabric GUID, not the Azure resource ID.
data "fabric_capacity" "capacity" {
  display_name = azurerm_fabric_capacity.main.name

  lifecycle {
    postcondition {
      condition     = self.state == "Active"
      error_message = "The new Fabric capacity must be Active and visible to the Fabric provider identity."
    }
  }
}

resource "fabric_workspace" "dev" {
  display_name = "${var.project_name}-dev"
  description  = "Development workspace; bootstrap from Git with a Fabric deployment plan."
  capacity_id  = data.fabric_capacity.capacity.id
}

resource "fabric_workspace" "test" {
  display_name = "${var.project_name}-test"
  description  = "Test workspace; initially empty, reserved for native Fabric deployments."
  capacity_id  = data.fabric_capacity.capacity.id
}

resource "fabric_connection" "github" {
  display_name      = "${var.project_name}-github-conn"
  connectivity_type = "ShareableCloud"
  privacy_level     = "Organizational"

  connection_details = {
    type            = "GitHubSourceControl"
    creation_method = "GitHubSourceControl.Contents"
    parameters      = [{ name = "url", value = local.github_repository_url }]
  }

  credential_details = {
    credential_type      = "Key"
    skip_test_connection = false
    key_credentials = {
      key_wo         = var.github_token
      key_wo_version = var.github_token_version
    }
  }
}

# Git initialization is performed outside Terraform so it can attach a deployment plan.
resource "fabric_deployment_pipeline" "main" {
  display_name = "${var.project_name}-promotion"
  description  = "Native Fabric item promotion; attach the reviewed deployment plan per operation."
  stages = [
    {
      display_name = "DEV"
      description  = "Git-connected development stage."
      is_public    = false
      workspace_id = fabric_workspace.dev.id
    },
    {
      display_name = "TEST"
      description  = "Validation stage; initially empty."
      is_public    = false
      workspace_id = fabric_workspace.test.id
    },
  ]
}

# The creator already has Admin; only grant Contributor to a separate user.
resource "fabric_workspace_role_assignment" "dev_contributor" {
  count = var.contributor_principal_id == null ? 0 : 1

  workspace_id = fabric_workspace.dev.id
  role         = "Contributor"
  principal = {
    id   = var.contributor_principal_id
    type = "User"
  }
}
