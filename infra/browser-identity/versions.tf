terraform {
  required_version = ">= 1.11, < 2.0"
  backend "azurerm" {}
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "= 3.10.0"
    }
  }
}

provider "azuread" {
  tenant_id = var.expected_tenant_id
  use_cli   = true
}
