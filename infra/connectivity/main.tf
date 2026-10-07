locals {
  name                   = "${var.project_name}-connectivity"
  router_subnet_cidr     = cidrsubnet(var.vnet_cidr, 11, 24)
  future_endpoint_prefix = cidrsubnet(var.vnet_cidr, 8, 2)
  tags                   = merge(var.tags, { project = var.project_name, environment = "poc", purpose = "connectivity", managed_by = "Terraform" })
}

resource "terraform_data" "approval" {
  lifecycle {
    precondition {
      condition     = var.poc_connectivity_approved
      error_message = "Obtain explicit synthetic-only PoC connectivity approval. Tailscale is not FIPS-validated and must not be treated as approval for regulated data."
    }
  }
}

resource "azurerm_resource_group" "connectivity" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
  lifecycle { prevent_destroy = true }
  depends_on = [terraform_data.approval]
}

resource "azurerm_virtual_network" "poc" {
  name                = "vnet-${var.project_name}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = var.location
  address_space       = [var.vnet_cidr]
  tags                = local.tags
  lifecycle { prevent_destroy = true }
}

resource "azurerm_subnet" "router" {
  name                            = "snet-${local.name}"
  resource_group_name             = azurerm_resource_group.connectivity.name
  virtual_network_name            = azurerm_virtual_network.poc.name
  address_prefixes                = [local.router_subnet_cidr]
  default_outbound_access_enabled = false
}

resource "azurerm_public_ip" "egress" {
  name                = "pip-${local.name}-egress"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "egress" {
  name                    = "nat-${local.name}"
  resource_group_name     = azurerm_resource_group.connectivity.name
  location                = var.location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "egress" {
  nat_gateway_id       = azurerm_nat_gateway.egress.id
  public_ip_address_id = azurerm_public_ip.egress.id
}

resource "azurerm_subnet_nat_gateway_association" "router" {
  subnet_id      = azurerm_subnet.router.id
  nat_gateway_id = azurerm_nat_gateway.egress.id
}

resource "azurerm_network_security_group" "router" {
  name                = "nsg-${local.name}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = var.location
  tags                = local.tags
  security_rule {
    name                       = "DenyUnsolicitedInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "router" {
  subnet_id                 = azurerm_subnet.router.id
  network_security_group_id = azurerm_network_security_group.router.id
}

resource "azurerm_network_interface" "router" {
  name                  = "nic-${local.name}"
  resource_group_name   = azurerm_resource_group.connectivity.name
  location              = var.location
  ip_forwarding_enabled = true
  tags                  = local.tags
  ip_configuration {
    name                          = "private"
    subnet_id                     = azurerm_subnet.router.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "router" {
  name                            = local.name
  computer_name                   = local.name
  resource_group_name             = azurerm_resource_group.connectivity.name
  location                        = var.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.router.id]
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  provision_vm_agent              = true
  allow_extension_operations      = true
  custom_data                     = base64encode(file("${path.module}/cloud-init.yaml"))
  tags                            = local.tags
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_public_key
  }
  os_disk {
    name                 = "os-${local.name}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = var.image_version
  }
  boot_diagnostics {}
  lifecycle { prevent_destroy = true }
  depends_on = [
    azurerm_nat_gateway_public_ip_association.egress,
    azurerm_subnet_nat_gateway_association.router,
    azurerm_subnet_network_security_group_association.router
  ]
}
