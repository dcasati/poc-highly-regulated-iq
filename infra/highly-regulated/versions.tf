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
    restful = {
      source  = "magodo/restful"
      version = "~> 0.25.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }

}

provider "kubernetes" {
  host                   = var.hosting == "aks" ? azurerm_kubernetes_cluster.app[0].kube_config[0].host : null
  cluster_ca_certificate = var.hosting == "aks" ? base64decode(azurerm_kubernetes_cluster.app[0].kube_config[0].cluster_ca_certificate) : null
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args        = ["get-token", "--login", "azurecli", "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"]
  }
}
provider "azapi" {}
provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
}

provider "restful" {
  base_url      = data.azurerm_search_service.existing.endpoint
  create_method = "PUT"
  update_method = "PUT"
  delete_method = "DELETE"
  header        = { Content-Type = "application/json" }
  query         = { api-version = ["2026-08-01-preview"] }
  security = {
    apikey = [{ in = "header", name = "Authorization", value = "Bearer ${var.search_access_token}" }]
  }
  client = {
    retry = { status_codes = [429, 500, 502, 503, 504], count = 6, wait_in_sec = 5, max_wait_in_sec = 30 }
  }
}

provider "restful" {
  alias         = "content"
  base_url      = var.content_endpoint
  create_method = "PUT"
  update_method = "PUT"
  delete_method = "DELETE"
  header        = { Content-Type = "application/json" }
  query         = { api-version = ["2025-11-01"] }
  security = {
    apikey = [{ in = "header", name = "Authorization", value = "Bearer ${var.content_access_token}" }]
  }
}
