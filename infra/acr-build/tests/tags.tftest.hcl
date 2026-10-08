mock_provider "azurerm" {
  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-4000-8000-000000000001/resourceGroups/demo-build"
    }
  }
  mock_data "azurerm_virtual_network" {
    defaults = {
      location = "westus3"
    }
  }
  mock_data "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-4000-8000-000000000001/resourceGroups/demo-network/providers/Microsoft.Network/virtualNetworks/demo-vnet/subnets/build"
    }
  }
  mock_resource "azurerm_container_registry_agent_pool" {
    override_during = plan
    defaults = {
      id = "/subscriptions/00000000-0000-4000-8000-000000000001/resourceGroups/demo-build/providers/Microsoft.ContainerRegistry/registries/demoregistry/agentPools/demoreviewpool"
    }
  }
}

mock_provider "azapi" {
  mock_data "azapi_resource" {
    defaults = {
      output = {
        location = "westus3"
        sku      = { name = "Premium" }
        properties = {
          loginServer         = "demoregistry.azurecr.io"
          publicNetworkAccess = "Disabled"
          privateEndpointConnections = [{
            properties = {
              privateLinkServiceConnectionState = { status = "Approved" }
            }
          }]
        }
      }
    }
  }
}

variables {
  project_name               = "demo-review"
  location                   = "westus3"
  registry                   = { name = "demoregistry", resource_group_name = "demo-build" }
  build_subnet               = { name = "build", virtual_network_name = "demo-vnet", resource_group_name = "demo-network" }
  preview_approved           = true
  network_approval_reference = "Synthetic mocked test only"
  tags                       = { purpose = "synthetic-test" }
}

run "idle_tags_remain_managed" {
  command = plan
  variables {
    instance_count = 0
  }
  assert {
    condition     = azurerm_container_registry_agent_pool.build.instance_count == 0
    error_message = "Idle tag ownership must not allocate a build instance."
  }
  assert {
    condition     = azapi_resource.pool_tags.parent_id == azurerm_container_registry_agent_pool.build.id
    error_message = "The tags child must be scoped only to the owned pool."
  }
  assert {
    condition     = azapi_resource.pool_tags.body.properties.tags == local.pool_tags && local.pool_tags.purpose == "synthetic-test"
    error_message = "The tags child must retain declared ownership and operator tags."
  }
}

run "allocated_tags_remain_managed" {
  command = plan
  variables {
    instance_count = 1
  }
  assert {
    condition     = azurerm_container_registry_agent_pool.build.instance_count == 1 && azapi_resource.pool_tags.body.properties.tags == local.pool_tags
    error_message = "Allocated and idle pools must use the same declarative tag owner."
  }
}
