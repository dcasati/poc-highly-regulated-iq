variable "project_name" {
  description = "Stable generic scenario name used for new resources, containers and knowledge objects."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.project_name)) && !strcontains(var.project_name, "--")
    error_message = "Use 3-16 lowercase letters, digits and single hyphens."
  }
}
variable "location" {
  description = "Explicit Azure region with approved model, Content Understanding, private Search and runtime support."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "Use an Azure region short name."
  }
}
variable "existing" {
  description = "Existing private resources. This root reads them and does not adopt or replace their infrastructure."
  type = object({
    foundry_name           = string
    foundry_resource_group = string
    project_name           = string
    agent_name             = string
    search_name            = string
    search_resource_group  = string
    storage_name           = string
    storage_resource_group = string
    vnet_name              = string
    network_resource_group = string
    runtime_subnet_name    = string
    endpoint_subnet_name   = string
    registry_dns_group     = string
    blob_shared_link_name  = string
  })
}
variable "existing_content_links" {
  description = "Existing approved Search shared-private-link names keyed by foundry_account and cognitiveservices_account. Missing entries are created, never duplicates."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for name in keys(var.existing_content_links) : contains(["foundry_account", "cognitiveservices_account"], name)])
    error_message = "Only Content Understanding processing and billing group IDs are supported."
  }
}
variable "content_endpoint" {
  description = "Verified existing Foundry Content Understanding HTTPS endpoint, without a trailing slash."
  type        = string
  validation {
    condition     = can(regex("^https://[a-z0-9-]+\\.(services\\.ai|cognitiveservices)\\.azure\\.com$", var.content_endpoint))
    error_message = "Use the discovered Foundry services.ai or cognitiveservices endpoint."
  }
}
variable "project_endpoint" {
  description = "Discovered existing Foundry project endpoint; do not derive it from an unverified project."
  type        = string
  validation {
    condition     = can(regex("^https://[a-z0-9-]+\\.services\\.ai\\.azure\\.com/api/projects/[A-Za-z0-9._-]+$", var.project_endpoint))
    error_message = "Use the verified HTTPS Foundry project endpoint."
  }
}
variable "identity" {
  description = "Administrator-approved SPA/API registration. API access token version 2, delegated scope and Caseworker/Reviewer roles are required."
  type = object({
    tenant_id     = string
    spa_client_id = string
    api_client_id = string
    api_scope     = string
  })
  validation {
    condition = alltrue([for id in [var.identity.tenant_id, var.identity.spa_client_id, var.identity.api_client_id] :
    can(regex("^[0-9a-fA-F-]{36}$", id))])
    error_message = "Identity values must be approved directory/application GUIDs."
  }
}
variable "hosting" {
  description = "Evaluate Container Apps first. Select AKS only if platform cryptography evidence or runtime constraints rule it out."
  type        = string
  default     = "container_apps"
  validation {
    condition     = contains(["container_apps", "aks"], var.hosting)
    error_message = "hosting must be container_apps or aks."
  }
}
variable "compliance" {
  description = "Approval record references, not certificates or secrets. FIPS validation belongs to cryptographic modules and their exact operating environments."
  type = object({
    approved           = bool
    platform_evidence  = string
    image_evidence     = string
    transport_evidence = string
  })
  default = {
    approved = false, platform_evidence = "", image_evidence = "", transport_evidence = ""
  }
}
variable "deploy_runtime" {
  description = "Enable only after ACR contains the reviewed image digest and compliance/network/identity gates are approved."
  type        = bool
  default     = false
}
variable "deploy_knowledge" {
  description = "Enable the custom analyzer, indexers, knowledge source/base and project connection after private dependency approvals."
  type        = bool
  default     = false
}
variable "image_digest" {
  description = "Immutable sha256 digest of review-portal in this scenario's ACR; never a mutable tag."
  type        = string
  default     = null
  validation {
    condition     = var.image_digest == null ? !var.deploy_runtime : can(regex("^sha256:[0-9a-f]{64}$", var.image_digest))
    error_message = "Runtime deployment requires a reviewed sha256 image digest."
  }
}
variable "search_access_token" {
  description = "Short-lived Search bearer token supplied through TF_VAR_search_access_token in each shell. Never persist or print."
  type        = string
  sensitive   = true
  ephemeral   = true
}
variable "content_access_token" {
  description = "Short-lived Cognitive Services bearer token supplied through TF_VAR_content_access_token."
  type        = string
  sensitive   = true
  ephemeral   = true
}
variable "analyzer_id" {
  description = "New, scenario-owned Content Understanding custom analyzer ID. Do not reuse a preexisting analyzer."
  type        = string
  default     = "application-review"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,64}$", var.analyzer_id))
    error_message = "Use a valid Content Understanding analyzer ID."
  }
}
variable "analyzer_fields" {
  description = "Generic scalar field schema. Extend in a derived repository using approved domain requirements."
  type = map(object({
    type        = string
    method      = string
    description = string
  }))
  default = {
    ApplicantName       = { type = "string", method = "extract", description = "Applicant or organization name exactly as written." }
    ReferenceNumber     = { type = "string", method = "extract", description = "Application reference number, if present." }
    RequestedCategory   = { type = "string", method = "extract", description = "Requested application category exactly as written." }
    Description         = { type = "string", method = "extract", description = "Applicant's description or purpose; do not infer eligibility." }
    SupportingDocuments = { type = "string", method = "extract", description = "Supporting documents explicitly identified in this package." }
    SignaturePresent    = { type = "boolean", method = "extract", description = "Whether a signature is visibly present. This does not establish validity or authority." }
  }
  validation {
    condition = length(var.analyzer_fields) > 0 && alltrue([for name, field in var.analyzer_fields :
      can(regex("^[A-Za-z][A-Za-z0-9_]{0,63}$", name)) &&
      contains(["string", "boolean", "number", "integer", "date"], field.type) &&
    field.method == "extract" && length(trimspace(field.description)) > 0])
    error_message = "Provide named scalar extraction fields with nonempty descriptions."
  }
}
variable "analyzer_models" {
  description = "Approved Content Understanding model names. Existing resource defaults must already map these to supported deployments."
  type        = object({ completion = string, embedding = string })
}
variable "confidence_threshold" {
  description = "UI attention threshold only. Every field still requires explicit human confirmation."
  type        = number
  default     = 0.9
  validation {
    condition     = var.confidence_threshold >= 0 && var.confidence_threshold <= 1
    error_message = "Use a confidence threshold between zero and one."
  }
}
variable "processing_location" {
  description = "Approved Content Understanding processing boundary. Global processing is deliberately not offered."
  type        = string
  default     = "geography"
  validation {
    condition     = contains(["geography", "dataZone"], var.processing_location)
    error_message = "Use a supported geography or dataZone boundary after confirming region/model support."
  }
}
variable "aks" {
  description = "Explicit supported AKS/FIPS versions and approved ingress inputs. No reference-repository versions are copied."
  type = object({
    kubernetes_version = string
    os_sku             = string
    vm_size            = string
    mesh_revision      = string
    private_ip         = string
    hostname           = string
    tls_secret_name    = string
    ingress_namespace  = string
    node_count         = optional(number, 3)
    pod_cidr           = optional(string, "10.244.0.0/16")
    service_cidr       = optional(string, "10.245.0.0/16")
    dns_service_ip     = optional(string, "10.245.0.10")
  })
  default = null
  validation {
    condition     = var.hosting != "aks" || var.aks != null
    error_message = "AKS requires explicitly reviewed versions, network ranges and ingress settings."
  }
  validation {
    condition = var.aks == null ? true : (
      contains(["AzureLinux3", "Ubuntu", "Ubuntu2204"], var.aks.os_sku) &&
      var.aks.node_count >= 2 && floor(var.aks.node_count) == var.aks.node_count &&
      can(cidrhost("${var.aks.private_ip}/32", 0)) &&
      can(cidrhost(var.aks.pod_cidr, 0)) && can(cidrhost(var.aks.service_cidr, 0)) &&
      can(regex("^[a-zA-Z0-9.-]+$", var.aks.hostname))
    )
    error_message = "Use a supported FIPS OS SKU, at least two nodes, valid IPv4 ranges and an internal hostname."
  }
}
variable "tags" {
  description = "Additional nonsensitive Azure tags."
  type        = map(string)
  default     = {}
}
