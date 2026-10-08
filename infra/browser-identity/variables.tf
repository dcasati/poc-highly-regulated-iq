variable "project_name" {
  description = "Unique PoC browser-identity branding; existing applications are never adopted."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.project_name)) && !strcontains(var.project_name, "--")
    error_message = "Use 3-16 lowercase letters, digits and single hyphens."
  }
}

variable "expected_tenant_id" {
  description = "Explicit approved directory for single-tenant applications and backend-independent identity checks."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.expected_tenant_id)) && var.expected_tenant_id != "00000000-0000-0000-0000-000000000000"
    error_message = "Provide the approved nonzero directory GUID."
  }
}

variable "spa_redirect_uris" {
  description = "Exact HTTPS portal URLs, added after private hosting returns its real hostname. Empty permits registration only, not browser readiness."
  type        = set(string)
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for uri in var.spa_redirect_uris : can(regex("^https://[^/?#]+/[^?#]*$", uri)) && !strcontains(uri, "*")])
    error_message = "Use exact HTTPS redirect URLs with a path, no wildcards, query strings or fragments."
  }
}

variable "assign_operator_roles" {
  description = "Explicit scoped approval to assign Caseworker/Reviewer on this new API to the current deployment user only. No directory or Azure resource role is granted."
  type        = bool
  default     = false
  nullable    = false
}
