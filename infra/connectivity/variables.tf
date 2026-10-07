variable "project_name" {
  description = "Generic branding for this new PoC network and connectivity VM; never adopt another project's resources."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.project_name)) && !strcontains(var.project_name, "--")
    error_message = "Use 3-16 lowercase letters, digits and single hyphens."
  }
}

variable "location" {
  description = "Explicit approved US region for every regional resource in this root."
  type        = string
  nullable    = false
  validation {
    condition = contains([
      "westus", "westus2", "westus3", "westcentralus", "centralus",
      "northcentralus", "southcentralus", "eastus", "eastus2"
    ], var.location)
    error_message = "This PoC requires a US Azure region; non-US resources must not be referenced or changed."
  }
}

variable "vm_size" {
  description = "Approved Linux VM SKU, after regional subscription restrictions and family/regional quota checks."
  type        = string
  nullable    = false
  validation {
    condition     = startswith(var.vm_size, "Standard_")
    error_message = "Provide the approved Standard VM SKU."
  }
}

variable "image_version" {
  description = "Explicit reviewed Canonical Ubuntu 24.04 server image version, available in the target region; not latest."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.image_version))
    error_message = "Use the exact published Ubuntu image version, not latest."
  }
}

variable "admin_username" {
  description = "Local administrator for key-only OpenSSH over the approved tailnet."
  type        = string
  default     = "iqadmin"
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,19}$", var.admin_username)) && !contains(["root", "admin", "administrator"], var.admin_username)
    error_message = "Use a nonreserved lowercase Linux username."
  }
}

variable "admin_public_key" {
  description = "Existing approved SSH public key. Never supply a private key or generate one into Terraform state."
  type        = string
  sensitive   = true
  nullable    = false
  validation {
    condition     = can(regex("^ssh-(ed25519|rsa) [A-Za-z0-9+/=]+( [^\\r\\n]*)?\\s*$", var.admin_public_key))
    error_message = "Provide a single Ed25519 or RSA SSH public key."
  }
}

variable "vnet_cidr" {
  description = "New, nonoverlapping RFC1918 10.x /16 network. Router uses its fourth /24's first /27; reserve the third /24 for future PoC private endpoints."
  type        = string
  default     = "10.20.0.0/16"
  nullable    = false
  validation {
    condition     = can(cidrnetmask(var.vnet_cidr)) && can(regex("^10\\.[0-9]+\\.0\\.0/16$", var.vnet_cidr))
    error_message = "Use a canonical private 10.x.0.0/16 network that does not overlap the client's local or tailnet routes."
  }
}

variable "os_disk_size_gb" {
  description = "Encrypted Standard SSD OS disk size. This VM retains tailnet node state locally after operator enrollment."
  type        = number
  default     = 32
  nullable    = false
  validation {
    condition     = var.os_disk_size_gb >= 32 && floor(var.os_disk_size_gb) == var.os_disk_size_gb
    error_message = "Use a whole-number disk size of at least 32 GiB."
  }
}

variable "poc_connectivity_approved" {
  description = "Explicit approval for synthetic-only Tailscale PoC administration. Tailscale is not FIPS-validated; this is not an application compliance approval."
  type        = bool
  default     = false
  nullable    = false
}

variable "tags" {
  description = "Additional nonsensitive tags; project, purpose and environment remain PoC-specific."
  type        = map(string)
  default     = {}
  nullable    = false
}
