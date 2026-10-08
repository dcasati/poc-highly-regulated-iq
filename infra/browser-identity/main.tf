data "azuread_client_config" "current" {}

locals {
  scope_id = uuidv5("url", "https://${var.expected_tenant_id}/${var.project_name}/access_as_user")
  role_ids = { for name in ["Caseworker", "Reviewer"] :
    name => uuidv5("url", "https://${var.expected_tenant_id}/${var.project_name}/roles/${name}")
  }
}

resource "terraform_data" "directory" {
  input = var.expected_tenant_id
  lifecycle {
    precondition {
      condition     = lower(data.azuread_client_config.current.tenant_id) == lower(var.expected_tenant_id)
      error_message = "The selected CLI directory does not match the approved browser-identity directory."
    }
  }
}

resource "azuread_application" "api" {
  display_name            = "${var.project_name}-review-api"
  sign_in_audience        = "AzureADMyOrg"
  prevent_duplicate_names = true
  owners                  = [data.azuread_client_config.current.object_id]
  api {
    requested_access_token_version = 2
    oauth2_permission_scope {
      id                         = local.scope_id
      value                      = "access_as_user"
      type                       = "User"
      enabled                    = true
      admin_consent_display_name = "Access the document-review API as the signed-in user"
      admin_consent_description  = "Access only the API actions authorized by assigned caseworker/reviewer roles."
      user_consent_display_name  = "Access the document-review API"
      user_consent_description   = "Access this private review portal using your assigned roles."
    }
  }
  dynamic "app_role" {
    for_each = local.role_ids
    content {
      id                   = app_role.value
      value                = app_role.key
      display_name         = app_role.key
      description          = "Perform ${app_role.key} actions in this document-review portal, not automated eligibility decisions."
      allowed_member_types = ["User"]
      enabled              = true
    }
  }
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [identifier_uris]
  }
  depends_on = [terraform_data.directory]
}

resource "azuread_application_identifier_uri" "api" {
  application_id = azuread_application.api.id
  identifier_uri = "api://${azuread_application.api.client_id}"
}

resource "azuread_application" "spa" {
  display_name            = "${var.project_name}-review-spa"
  sign_in_audience        = "AzureADMyOrg"
  prevent_duplicate_names = true
  owners                  = [data.azuread_client_config.current.object_id]
  single_page_application {
    redirect_uris = var.spa_redirect_uris
  }
  required_resource_access {
    resource_app_id = azuread_application.api.client_id
    resource_access {
      id   = local.scope_id
      type = "Scope"
    }
  }
  lifecycle {
    prevent_destroy = true
  }
  depends_on = [terraform_data.directory]
}

resource "azuread_service_principal" "api" {
  client_id                    = azuread_application.api.client_id
  owners                       = [data.azuread_client_config.current.object_id]
  app_role_assignment_required = true
}

resource "azuread_service_principal" "spa" {
  client_id = azuread_application.spa.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_pre_authorized" "spa" {
  application_id       = azuread_application.api.id
  authorized_client_id = azuread_application.spa.client_id
  permission_ids       = [local.scope_id]
  depends_on           = [azuread_application_identifier_uri.api]
}

resource "azuread_app_role_assignment" "operator" {
  for_each            = var.assign_operator_roles ? local.role_ids : {}
  app_role_id         = each.value
  principal_object_id = data.azuread_client_config.current.object_id
  resource_object_id  = azuread_service_principal.api.object_id
}
