mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000002"
      object_id = "00000000-0000-0000-0000-000000000003"
    }
  }
}

variables {
  project_name       = "unitpoc"
  expected_tenant_id = "00000000-0000-0000-0000-000000000002"
}

run "registration_without_access" {
  command = plan
  assert {
    condition = (
      azuread_application.api.sign_in_audience == "AzureADMyOrg" &&
      azuread_application.spa.sign_in_audience == "AzureADMyOrg" &&
      azuread_application.api.api[0].requested_access_token_version == 2 &&
      azuread_service_principal.api.app_role_assignment_required &&
      length(azuread_app_role_assignment.operator) == 0 &&
      length(azuread_application.api.app_role) == 2 &&
      length(azuread_application.spa.required_resource_access) == 1
    )
    error_message = "Default registrations must be single-tenant/v2, API role-restricted and request no Graph privileges or operator access."
  }
}

run "operator_access_is_scoped" {
  command = plan
  variables {
    assign_operator_roles = true
  }
  assert {
    condition = (
      toset(keys(azuread_app_role_assignment.operator)) == toset(["Caseworker", "Reviewer"]) &&
      alltrue([for grant in azuread_app_role_assignment.operator :
        grant.principal_object_id == data.azuread_client_config.current.object_id
      ]) &&
      azuread_application_pre_authorized.spa.permission_ids == toset([local.scope_id])
    )
    error_message = "Only the current operator receives this API's two roles, and the SPA is preauthorized for only the custom delegated scope."
  }
}

run "reject_foreign_directory" {
  command = plan
  variables {
    expected_tenant_id = "00000000-0000-0000-0000-000000000004"
  }
  expect_failures = [terraform_data.directory]
}

run "reject_untrusted_redirect" {
  command = plan
  variables {
    spa_redirect_uris = ["http://untrusted.example/"]
  }
  expect_failures = [var.spa_redirect_uris]
}
