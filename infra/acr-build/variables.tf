variable "project_name" {
  description = "Generic build-pool branding. Choose a unique name; do not adopt another project's pool."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.project_name)) && !strcontains(var.project_name, "--")
    error_message = "Use 3-16 lowercase letters, digits and single hyphens."
  }
}

variable "location" {
  description = "Explicit approved agent-pool region. Must match the existing registry and build VNet, and support the agent-pool preview."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "Use an Azure region short name."
  }
}

variable "registry" {
  description = "Existing private Premium ACR. This root reads its configuration and owns only the new agent pool."
  type = object({
    name                = string
    resource_group_name = string
  })
  nullable = false
  validation {
    condition = (
      can(regex("^[a-z0-9]{5,50}$", var.registry.name)) &&
      length(trimspace(var.registry.resource_group_name)) > 0
    )
    error_message = "Provide a valid existing registry name and its resource group."
  }
}

variable "build_subnet" {
  description = "Administrator-approved dedicated existing subnet in the selected subscription, with private ACR DNS/connectivity and approved build-service egress."
  type = object({
    name                 = string
    virtual_network_name = string
    resource_group_name  = string
  })
  nullable = false
  validation {
    condition     = alltrue([for value in values(var.build_subnet) : length(trimspace(value)) > 0])
    error_message = "Provide the approved subnet, VNet and network resource-group names."
  }
}

variable "tier" {
  description = "ACR agent-pool tier. S1/S2/S3 consume 2/4/8 vCPUs per instance; I6 consumes 64 and needs separately approved isolated-pool quota."
  type        = string
  default     = "S2"
  nullable    = false
  validation {
    condition     = contains(["S1", "S2", "S3", "I6"], var.tier)
    error_message = "Use a supported ACR agent-pool tier."
  }
}

variable "instance_count" {
  description = "Allocated, billable instances. At least one is needed to build; scale to zero only through a separately approved plan after queued work finishes."
  type        = number
  default     = 1
  nullable    = false
  validation {
    condition     = var.instance_count >= 0 && floor(var.instance_count) == var.instance_count
    error_message = "Use a nonnegative whole number of agent instances."
  }
}

variable "preview_approved" {
  description = "Set true only after the authorized organization accepts the ACR agent-pool preview and its terms/limitations."
  type        = bool
  default     = false
  nullable    = false
}

variable "network_approval_reference" {
  description = "Nonsensitive approval record for the existing build subnet, DNS, routing and required outbound destinations. Not proof of live connectivity."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.network_approval_reference)) > 0
    error_message = "Record the authorized network approval before provisioning the pool."
  }
}

variable "tags" {
  description = "Additional nonsensitive tags for the new agent pool, not the existing registry."
  type        = map(string)
  default     = {}
  nullable    = false
}
