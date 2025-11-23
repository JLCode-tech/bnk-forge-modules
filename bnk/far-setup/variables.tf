# infrastructure-modules/spk-2.1/far-setup/variables.tf

# =============================================================================
# REQUIRED VARIABLES
# =============================================================================

variable "spk_manifest_version" {
  description = "SPK manifest version to download from FAR"
  type        = string
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+\\.[0-9]+\\.[0-9]+$", var.spk_manifest_version))
    error_message = "SPK manifest version must follow format: X.Y.Z-A.B.C-D.E.F (e.g., 2.1.0-3.1736.1-0.1.27)"
  }
}

variable "manifest_chart_name" {
  description = "Name of the F5 manifest chart in FAR"
  type        = string
  default     = "f5-bigip-k8s-manifest"
}

variable "service_account_key_file" {
  description = "Path to F5 FAR service account key JSON file"
  type        = string
  validation {
    condition     = can(file(var.service_account_key_file))
    error_message = "Service account key file must exist and be readable"
  }
}

variable "spk_namespace" {
  description = "Kubernetes namespace for SPK controller and TMM components"
  type        = string
  default     = "f5-spk"
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.spk_namespace))
    error_message = "Namespace must be valid Kubernetes namespace name (lowercase alphanumeric and hyphens)"
  }
}

variable "utils_namespace" {
  description = "Kubernetes namespace for shared F5 utility components"
  type        = string
  default     = "f5-utils"
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.utils_namespace))
    error_message = "Namespace must be valid Kubernetes namespace name (lowercase alphanumeric and hyphens)"
  }
}

# =============================================================================
# OPTIONAL VARIABLES
# =============================================================================

variable "create_namespaces" {
  description = "Whether to create the SPK and utils namespaces"
  type        = bool
  default     = true
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

# =============================================================================
# DEPENDENCY INPUTS
# =============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for resource naming and identification)"
  type        = string
}