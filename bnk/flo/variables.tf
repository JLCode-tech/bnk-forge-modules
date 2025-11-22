# infrastructure-modules/spk-2.1/flo/variables.tf
# F5 Lifecycle Operator Module Variables

# =============================================================================
# REQUIRED VARIABLES
# =============================================================================

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "flo_namespace" {
  description = "Kubernetes namespace for F5 Lifecycle Operator"
  type        = string
  default     = "f5-operators"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.flo_namespace))
    error_message = "Namespace must be valid Kubernetes namespace name (lowercase alphanumeric and hyphens)"
  }
}

variable "far_secret_name" {
  description = "Name of the FAR pull secret (from far-setup outputs)"
  type        = string
}

variable "flo_version" {
  description = "Version of F5 Lifecycle Operator Helm chart"
  type        = string
  default     = "v1.198.4-0.1.36"
}

# =============================================================================
# LICENSING CONFIGURATION
# =============================================================================

variable "license_mode" {
  description = "License operation mode: connected or f5licenseproxy"
  type        = string
  default     = "connected"

  validation {
    condition     = contains(["connected", "f5licenseproxy"], var.license_mode)
    error_message = "License mode must be either 'connected' or 'f5licenseproxy'"
  }
}

variable "license_environment" {
  description = "Licensing environment: production or test"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "test"], var.license_environment)
    error_message = "license_environment must be either 'production' or 'test'"
  }
}

variable "jwt_token" {
  description = "JWT token for F5 licensing (required for connected mode)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "f5_license_proxy_url" {
  description = "F5 License Proxy URL (required if license_mode is f5licenseproxy)"
  type        = string
  default     = ""
}

# =============================================================================
# REGISTRY AND IMAGE CONFIGURATION
# =============================================================================

variable "image_registry" {
  description = "F5 image registry for FLO components"
  type        = string
  default     = "repo.f5.com/images"
}

variable "flo_chart_repository" {
  description = "Helm chart repository for FLO"
  type        = string
  default     = "oci://repo.f5.com/charts"
}

# =============================================================================
# IPAM OPERATOR CONFIGURATION
# =============================================================================

variable "enable_ipam_operator" {
  description = "Enable IPAM operator deployment (deployed automatically with FLO)"
  type        = bool
  default     = true
}

variable "ipam_namespace" {
  description = "Namespace for IPAM operator resources"
  type        = string
  default     = "f5-ipam"
}

# =============================================================================
# RESOURCE CONFIGURATION
# =============================================================================

variable "flo_cpu_request" {
  description = "CPU request for FLO pods"
  type        = string
  default     = "100m"
}

variable "flo_memory_request" {
  description = "Memory request for FLO pods"
  type        = string
  default     = "128Mi"
}

variable "flo_cpu_limit" {
  description = "CPU limit for FLO pods"
  type        = string
  default     = "500m"
}

variable "flo_memory_limit" {
  description = "Memory limit for FLO pods"
  type        = string
  default     = "512Mi"
}

# =============================================================================
# NODE PLACEMENT
# =============================================================================

variable "node_selector" {
  description = "Node selector for FLO pod placement"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for FLO pod placement"
  type        = list(any)
  default     = []
}

# =============================================================================
# DEPENDENCY INPUTS
# =============================================================================

variable "cert_manager_ready" {
  description = "Dependency flag indicating cert-manager is ready"
  type        = bool
}

variable "far_setup_complete" {
  description = "Dependency flag indicating FAR setup is complete"
  type        = bool
}

# =============================================================================
# TAGS AND LABELS
# =============================================================================

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "common_labels" {
  description = "Common labels to apply to all Kubernetes resources"
  type        = map(string)
  default     = {}
}
