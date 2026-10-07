variable "project_name" {
  description = "Existing generic PoC branding, matching the separately owned connectivity root."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.project_name)) && !strcontains(var.project_name, "--")
    error_message = "Use 3-16 lowercase letters, digits and single hyphens."
  }
}

variable "location" {
  description = "Explicit US backend region; must match the verified PoC connectivity VNet."
  type        = string
  nullable    = false
  validation {
    condition = contains([
      "westus", "westus2", "westus3", "westcentralus", "centralus",
      "northcentralus", "southcentralus", "eastus", "eastus2"
    ], var.location)
    error_message = "All regional backend resources must remain in the US."
  }
}

variable "connectivity_network" {
  description = "Verified new PoC VNet from connectivity outputs, not unrelated infrastructure."
  type = object({
    name                = string
    resource_group_name = string
  })
  nullable = false
  validation {
    condition     = var.connectivity_network.name == "vnet-${var.project_name}" && var.connectivity_network.resource_group_name == "rg-${var.project_name}-connectivity"
    error_message = "Use this PoC's separately owned connectivity VNet and resource group."
  }
}

variable "container_name" {
  description = "Private Terraform state container; each root needs its own blob key."
  type        = string
  default     = "tfstate"
  nullable    = false
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.container_name)) && !strcontains(var.container_name, "--")
    error_message = "Use a valid 3-63 character lowercase Blob container name."
  }
}

variable "retention_days" {
  description = "Blob/container soft-delete retention. Versions remain enabled without automatic expiration; this is not immutable retention."
  type        = number
  default     = 30
  nullable    = false
  validation {
    condition     = var.retention_days >= 7 && var.retention_days <= 365 && floor(var.retention_days) == var.retention_days
    error_message = "Use a whole-number soft-delete retention of 7-365 days."
  }
}

variable "deployment_principal_type" {
  description = "Verified current ARM deployment identity type for the container-scoped role grant; not a new identity."
  type        = string
  nullable    = false
  validation {
    condition     = contains(["User", "ServicePrincipal"], var.deployment_principal_type)
    error_message = "Use the verified User or ServicePrincipal identity type."
  }
}

variable "backend_bootstrap_approved" {
  description = "Explicit acceptance of owner-only local state on the encrypted authoritative host for this backend bootstrap only; not approval to apply or migrate."
  type        = bool
  default     = false
  nullable    = false
}

variable "tags" {
  description = "Additional nonsensitive tags; project and backend purpose remain PoC-specific."
  type        = map(string)
  default     = {}
  nullable    = false
}
