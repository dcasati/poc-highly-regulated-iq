terraform {
  required_version = ">= 1.11, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
    fabric = {
      source  = "microsoft/fabric"
      version = "~> 1.14.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    restful = {
      source  = "magodo/restful"
      version = "~> 0.25.2"
    }
  }
}