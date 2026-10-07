terraform {
  required_version = ">= 1.11, < 2.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.8.0"
    }
  }
}

provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
}
