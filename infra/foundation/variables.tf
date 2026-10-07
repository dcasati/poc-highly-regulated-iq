variable "project_name" {
  description = "Generic branding matching the separately owned PoC connectivity and backend."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.project_name)) && !strcontains(var.project_name, "--")
    error_message = "Use 3-16 lowercase letters, digits and single hyphens."
  }
}

variable "location" {
  description = "Explicit approved US region; verify the selected models and private setup are supported there."
  type        = string
  nullable    = false
  validation {
    condition = contains([
      "westus", "westus2", "westus3", "westcentralus", "centralus",
      "northcentralus", "southcentralus", "eastus", "eastus2"
    ], var.location)
    error_message = "All regional foundation resources must be in the US."
  }
}

variable "expected_context" {
  description = "Verified deployment subscription/directory/principal; real values belong only in ignored local configuration."
  type = object({
    subscription_id = string
    tenant_id       = string
    object_id       = string
    principal_type  = string
  })
  nullable = false
  validation {
    condition = alltrue([for id in [var.expected_context.subscription_id, var.expected_context.tenant_id, var.expected_context.object_id] :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ]) && contains(["User", "ServicePrincipal"], var.expected_context.principal_type)
    error_message = "Supply the verified GUIDs and User or ServicePrincipal deployment identity type."
  }
}

variable "network" {
  description = "Separately owned PoC network, endpoint subnet and backend-owned Blob DNS zone."
  type = object({
    name                    = string
    resource_group_name     = string
    endpoint_subnet_name    = string
    blob_dns_resource_group = string
  })
  nullable = false
  validation {
    condition = (
      var.network.name == "vnet-${var.project_name}" &&
      var.network.resource_group_name == "rg-${var.project_name}-connectivity" &&
      var.network.endpoint_subnet_name == "snet-${var.project_name}-private-endpoints" &&
      var.network.blob_dns_resource_group == "rg-${var.project_name}-state"
    )
    error_message = "Reference only this PoC's separately owned connectivity and backend resources."
  }
}

variable "capability_preview_approved" {
  description = "Explicit acceptance of capability-settings API 2026-07-15-preview, not apply or production approval."
  type        = bool
  default     = false
  nullable    = false
}

variable "models" {
  description = "Approved US Data Zone chat and embedding model deployments; capacity units are model-specific."
  type = object({
    chat = object({
      name = string, version = string, capacity = number, sku = string
    })
    embedding = object({
      name = string, version = string, capacity = number, sku = string
    })
  })
  default = {
    chat      = { name = "gpt-5.2", version = "2025-12-11", capacity = 10, sku = "DataZoneStandard" }
    embedding = { name = "text-embedding-3-large", version = "1", capacity = 10, sku = "DataZoneStandard" }
  }
  nullable = false
  validation {
    condition = alltrue([for model in [var.models.chat, var.models.embedding] :
      model.sku == "DataZoneStandard" &&
      model.capacity >= 1 && floor(model.capacity) == model.capacity &&
      length(trimspace(model.name)) > 0 && length(trimspace(model.version)) > 0
    ])
    error_message = "Use approved explicit versions, whole-number capacity and US DataZoneStandard, never Global SKUs."
  }
}

variable "retention_days" {
  description = "Blob/container soft-delete retention; versioning is enabled. This is not locked immutable retention."
  type        = number
  default     = 30
  nullable    = false
  validation {
    condition     = var.retention_days >= 7 && var.retention_days <= 365 && floor(var.retention_days) == var.retention_days
    error_message = "Use a whole-number retention of 7-365 days."
  }
}

variable "provision_project" {
  description = "Enable in a separately reviewed stage after foundation private connectivity and caller-role propagation are verified."
  type        = bool
  default     = false
  nullable    = false
}

variable "private_connectivity_verified" {
  description = "Operator verification of normal OS service/CNAME DNS, private HTTPS and keyless store access before project provisioning."
  type        = bool
  default     = false
  nullable    = false
}

variable "configure_agent_runtime" {
  description = "Enable only after discovering and verifying the project's service-owned runtime identities and data resources."
  type        = bool
  default     = false
  nullable    = false
  validation {
    condition     = !var.configure_agent_runtime || var.provision_project
    error_message = "Runtime role configuration requires the provisioned project."
  }
}

variable "agent_runtime" {
  description = "Verified service-created bindings, not proposed names. Grant no runtime roles until discovery and separate saved-plan review."
  type = object({
    principal_ids          = set(string)
    files_container        = string
    intermediate_container = string
    database_name          = string
    verification_reference = string
  })
  default = {
    principal_ids = [], files_container = "", intermediate_container = "",
    database_name = "", verification_reference = ""
  }
  nullable = false
  validation {
    condition = !var.configure_agent_runtime || (
      length(var.agent_runtime.principal_ids) >= 1 &&
      alltrue([for id in var.agent_runtime.principal_ids : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))]) &&
      alltrue([for name in [var.agent_runtime.files_container, var.agent_runtime.intermediate_container] :
        can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", name)) && !strcontains(name, "--")
      ]) &&
      var.agent_runtime.files_container != var.agent_runtime.intermediate_container &&
      can(regex("^[A-Za-z0-9._-]{1,255}$", var.agent_runtime.database_name)) &&
      length(trimspace(var.agent_runtime.verification_reference)) > 0
    )
    error_message = "Runtime configuration requires verified identity GUIDs, distinct existing containers, database and an evidence reference."
  }
}

variable "tags" {
  description = "Additional nonsensitive tags; foundation ownership tags cannot be overridden."
  type        = map(string)
  default     = {}
  nullable    = false
}
