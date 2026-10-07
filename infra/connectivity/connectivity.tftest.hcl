mock_provider "azurerm" {}

variables {
  project_name              = "testpoc"
  location                  = "westus3"
  vm_size                   = "Standard_D2s_v4"
  image_version             = "24.04.202609040"
  poc_connectivity_approved = true
}

run "private_us_plan" {
  command = plan

  assert {
    condition     = azurerm_linux_virtual_machine.router.location == "westus3" && azurerm_virtual_network.poc.location == "westus3"
    error_message = "All regional resources must remain in the selected US region."
  }
  assert {
    condition     = azurerm_network_interface.router.ip_configuration[0].public_ip_address_id == null
    error_message = "The router VM must not have a public IP."
  }
  assert {
    condition     = azurerm_linux_virtual_machine.router.disable_password_authentication && azurerm_linux_virtual_machine.router.secure_boot_enabled && azurerm_linux_virtual_machine.router.vtpm_enabled
    error_message = "Preserve key-only login and Trusted Launch."
  }
  assert {
    condition     = length(azurerm_network_security_group.router.security_rule) == 1 && one(azurerm_network_security_group.router.security_rule).access == "Deny" && one(azurerm_network_security_group.router.security_rule).direction == "Inbound"
    error_message = "Do not permit unsolicited inbound VNet or Internet traffic."
  }
  assert {
    condition     = !azurerm_subnet.router.default_outbound_access_enabled && azurerm_network_interface.router.ip_forwarding_enabled
    error_message = "Routing needs NIC forwarding and explicit NAT, not implicit public outbound access."
  }
  assert {
    condition     = length(azurerm_subnet.router.address_prefixes) == 1 && azurerm_subnet.router.address_prefixes[0] == "10.20.3.0/27" && output.future_endpoint_prefix == "10.20.2.0/24"
    error_message = "The router and future endpoint prefix must occupy distinct parts of the new PoC network."
  }
  assert {
    condition     = strcontains(yamldecode(base64decode(azurerm_linux_virtual_machine.router.custom_data)).write_files[1].content, "interface=tailscale0") && strcontains(yamldecode(base64decode(azurerm_linux_virtual_machine.router.custom_data)).write_files[1].content, "except-interface=lo")
    error_message = "DNS must bind to Tailscale only, not the Azure NIC or loopback."
  }
  assert {
    condition     = length(regexall("auth-key|authkey|tailscale up", base64decode(azurerm_linux_virtual_machine.router.custom_data))) == 0
    error_message = "Cloud-init must not contain enrollment credentials or enroll the node."
  }
  assert {
    condition     = yamldecode(base64decode(azurerm_linux_virtual_machine.router.custom_data)).runcmd[0][0] == "/usr/local/sbin/provision-poc-connectivity"
    error_message = "Cloud-init must run the fail-fast provisioning script."
  }
}

run "non_us_region_rejected" {
  command = plan
  variables {
    location = "canadacentral"
  }
  expect_failures = [var.location]
}

run "approval_required" {
  command = plan
  variables {
    poc_connectivity_approved = false
  }
  expect_failures = [terraform_data.approval]
}

run "noncanonical_network_rejected" {
  command = plan
  variables {
    vnet_cidr = "10.20.3.0/16"
  }
  expect_failures = [var.vnet_cidr]
}
