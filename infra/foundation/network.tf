locals {
  subnets = {
    agent   = { number = 0, delegated = true }
    runtime = { number = 1, delegated = true }
    build   = { number = 4, delegated = false }
  }
  dns_zones = {
    cognitive = "privatelink.cognitiveservices.azure.com"
    openai    = "privatelink.openai.azure.com"
    foundry   = "privatelink.services.ai.azure.com"
    search    = "privatelink.search.windows.net"
    cosmos    = "privatelink.documents.azure.com"
    registry  = "privatelink.azurecr.io"
  }
  platform_egress = {
    build = {
      mcr      = { tag = "MicrosoftContainerRegistry", ports = ["443"] }
      mcr_data = { tag = "AzureFrontDoor.FirstParty", ports = ["443"] }
      keyvault = { tag = "AzureKeyVault", ports = ["443"] }
      storage  = { tag = "Storage", ports = ["443"] }
      eventhub = { tag = "EventHub", ports = ["443"] }
      monitor  = { tag = "AzureMonitor", ports = ["443", "12000"] }
    }
    runtime = {
      mcr      = { tag = "MicrosoftContainerRegistry", ports = ["443"] }
      mcr_data = { tag = "AzureFrontDoor.FirstParty", ports = ["443"] }
      storage  = { tag = "Storage.${var.location}", ports = ["443"] }
    }
  }
}

resource "azurerm_public_ip" "platform_egress" {
  count               = var.provision_platform_egress ? 1 : 0
  name                = "pip-${var.project_name}-platform-egress"
  resource_group_name = azurerm_resource_group.foundation.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "platform_egress" {
  count               = var.provision_platform_egress ? 1 : 0
  name                = "nat-${var.project_name}-platform-egress"
  resource_group_name = azurerm_resource_group.foundation.name
  location            = var.location
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "platform_egress" {
  count                = var.provision_platform_egress ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.platform_egress[0].id
  public_ip_address_id = azurerm_public_ip.platform_egress[0].id
}

resource "azurerm_subnet_nat_gateway_association" "platform_egress" {
  for_each       = var.provision_platform_egress ? local.platform_egress : {}
  subnet_id      = azurerm_subnet.foundation[each.key].id
  nat_gateway_id = azurerm_nat_gateway.platform_egress[0].id
}

resource "azurerm_subnet" "foundation" {
  for_each                        = local.subnets
  name                            = "snet-${var.project_name}-${each.key}"
  resource_group_name             = data.azurerm_virtual_network.poc.resource_group_name
  virtual_network_name            = data.azurerm_virtual_network.poc.name
  address_prefixes                = [cidrsubnet(data.azurerm_virtual_network.poc.address_space[0], 8, each.value.number)]
  default_outbound_access_enabled = false
  dynamic "delegation" {
    for_each = each.value.delegated ? [true] : []
    content {
      name = "container-apps"
      service_delegation {
        name    = "Microsoft.App/environments"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }
  lifecycle { prevent_destroy = true }
  depends_on = [terraform_data.gates]
}

resource "azurerm_network_security_group" "foundation" {
  for_each            = local.subnets
  name                = "nsg-${var.project_name}-${each.key}"
  resource_group_name = azurerm_resource_group.foundation.name
  location            = var.location
  tags                = local.tags
  dynamic "security_rule" {
    for_each = var.provision_platform_egress ? lookup(local.platform_egress, each.key, {}) : {}
    content {
      name                       = "platform-${security_rule.key}"
      priority                   = 200 + index(sort(keys(local.platform_egress[each.key])), security_rule.key)
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = security_rule.value.ports
      source_address_prefix      = "*"
      destination_address_prefix = security_rule.value.tag
    }
  }
  security_rule {
    name                       = "subnet-internal"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = cidrsubnet(data.azurerm_virtual_network.poc.address_space[0], 8, each.value.number)
  }
  security_rule {
    name                       = "private-endpoint-https"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = data.azurerm_subnet.endpoints.address_prefixes[0]
  }
  security_rule {
    name                       = "azure-dns"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "*"
    destination_address_prefix = "168.63.129.16/32"
  }
  security_rule {
    name                       = "entra-https"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureActiveDirectory"
  }
  security_rule {
    name                       = "deny-other-egress"
    priority                   = 4096
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "foundation" {
  for_each                  = local.subnets
  subnet_id                 = azurerm_subnet.foundation[each.key].id
  network_security_group_id = azurerm_network_security_group.foundation[each.key].id
}

resource "azurerm_private_dns_zone" "foundation" {
  for_each            = local.dns_zones
  name                = each.value
  resource_group_name = azurerm_resource_group.foundation.name
  tags                = local.tags
  lifecycle { prevent_destroy = true }
}

resource "azurerm_private_dns_zone_virtual_network_link" "foundation" {
  for_each             = local.dns_zones
  name                 = "link-${var.project_name}"
  private_dns_zone_id  = azurerm_private_dns_zone.foundation[each.key].id
  virtual_network_id   = data.azurerm_virtual_network.poc.id
  registration_enabled = false
  tags                 = local.tags
}

locals {
  endpoints = {
    foundry = {
      id    = azapi_resource.foundry.id, group = "account"
      zones = [for name in ["cognitive", "openai", "foundry"] : azurerm_private_dns_zone.foundation[name].id]
    }
    search = {
      id    = azurerm_search_service.foundation.id, group = "searchService"
      zones = [azurerm_private_dns_zone.foundation["search"].id]
    }
    application_blob = {
      id    = azurerm_storage_account.foundation["application"].id, group = "blob"
      zones = [data.azurerm_private_dns_zone.blob.id]
    }
    agent_blob = {
      id    = azurerm_storage_account.foundation["agent"].id, group = "blob"
      zones = [data.azurerm_private_dns_zone.blob.id]
    }
    cosmos = {
      id    = azurerm_cosmosdb_account.agent.id, group = "Sql"
      zones = [azurerm_private_dns_zone.foundation["cosmos"].id]
    }
  }
}

resource "azurerm_private_endpoint" "foundation" {
  for_each            = local.endpoints
  name                = "pe-${local.prefix}-${replace(each.key, "_", "-")}"
  resource_group_name = azurerm_resource_group.foundation.name
  location            = var.location
  subnet_id           = data.azurerm_subnet.endpoints.id
  tags                = local.tags
  private_service_connection {
    name                           = each.key
    private_connection_resource_id = each.value.id
    subresource_names              = [each.value.group]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "private"
    private_dns_zone_ids = each.value.zones
  }
}
