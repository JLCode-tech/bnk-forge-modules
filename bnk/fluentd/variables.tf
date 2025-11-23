# infrastructure-modules/spk-2.1/fluentd/variables.tf

# =============================================================================
# CLUSTER CONFIGURATION
# =============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for resource naming and identification)"
  type        = string
}

# =============================================================================
# NAMESPACE AND RELEASE
# =============================================================================

variable "namespace" {
  description = "Kubernetes namespace for Fluentd deployment"
  type        = string
}

variable "release_name" {
  description = "Helm release name for Fluentd"
  type        = string
  default     = "f5-toda-fluentd"
}

# =============================================================================
# VERSION CONFIGURATION
# =============================================================================

variable "fluentd_version" {
  description = "Version of f5-toda-fluentd Helm chart from FAR manifest"
  type        = string
}

# =============================================================================
# IMAGE REGISTRY CONFIGURATION
# =============================================================================

variable "image_registry" {
  description = "Docker image registry URL"
  type        = string
}

variable "far_secret_name" {
  description = "Name of the Kubernetes secret containing FAR registry credentials"
  type        = string
}

# =============================================================================
# STORAGE CONFIGURATION
# =============================================================================

variable "storage_class" {
  description = "Storage class for persistent volume (e.g., gp3)"
  type        = string
}

variable "storage_size" {
  description = "Size of persistent volume for Fluentd logs"
  type        = string
  default     = "10Gi"
}

# =============================================================================
# RESOURCE CONFIGURATION
# =============================================================================

variable "resources" {
  description = "Resource requests and limits for Fluentd"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

variable "node_selector" {
  description = "Node selector for pod assignment"
  type        = map(string)
  default     = {}
}

# =============================================================================
# DEPENDENCIES
# =============================================================================

variable "far_setup_complete" {
  description = "Flag indicating FAR setup is complete"
  type        = bool
}

variable "cert_manager_complete" {
  description = "Flag indicating cert-manager is complete"
  type        = bool
}

variable "storage_classes_deployed" {
  description = "Number of storage classes deployed - verifies storage module completion"
  type        = number
}