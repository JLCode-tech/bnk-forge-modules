# infrastructure-modules/spk-2.1/bnk-gatewayclass/variables.tf
# BNKGatewayClass Module Variables

# =============================================================================
# REQUIRED VARIABLES
# =============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for resource naming and identification)"
  type        = string
}

variable "gatewayclass_name" {
  description = "Name of the BNKGatewayClass resource"
  type        = string
  default     = "bnk-gatewayclass"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.gatewayclass_name))
    error_message = "GatewayClass name must be valid Kubernetes resource name"
  }
}

variable "controller_namespace" {
  description = "Namespace where F5 controller is deployed (typically f5-spk)"
  type        = string
}

variable "flo_namespace" {
  description = "Namespace where FLO is deployed (BNKGatewayClass must be in same namespace as FLO)"
  type        = string
}

# =============================================================================
# CONTROLLER CONFIGURATION
# =============================================================================

variable "controller_name" {
  description = "Controller name for BNKGatewayClass (F5 specific)"
  type        = string
  default     = "f5.com/gateway-controller"
}

variable "description" {
  description = "Description of the GatewayClass"
  type        = string
  default     = "F5 BIG-IP Next for Kubernetes Gateway Class"
}

# =============================================================================
# GATEWAY CLASS PARAMETERS
# =============================================================================

variable "default_tmm_replicas" {
  description = "Default number of TMM (Traffic Management Microkernel) replicas"
  type        = number
  default     = 2

  validation {
    condition     = var.default_tmm_replicas >= 1 && var.default_tmm_replicas <= 10
    error_message = "TMM replicas must be between 1 and 10"
  }
}

variable "default_service_type" {
  description = "Default service type for Gateway (LoadBalancer or ClusterIP)"
  type        = string
  default     = "LoadBalancer"

  validation {
    condition     = contains(["LoadBalancer", "ClusterIP"], var.default_service_type)
    error_message = "Service type must be LoadBalancer or ClusterIP"
  }
}

variable "enable_ipam" {
  description = "Enable IPAM (IP Address Management) for Gateway services"
  type        = bool
  default     = true
}

variable "ipam_namespace" {
  description = "Namespace for IPAM operator"
  type        = string
  default     = "f5-ipam"
}

# =============================================================================
# TMM RESOURCE DEFAULTS
# =============================================================================

variable "default_tmm_cpu" {
  description = "Default CPU allocation for TMM pods"
  type        = string
  default     = "2"
}

variable "default_tmm_memory" {
  description = "Default memory allocation for TMM pods"
  type        = string
  default     = "4Gi"
}

variable "default_tmm_hugepages_2mi" {
  description = "Default hugepages 2Mi allocation for TMM pods"
  type        = string
  default     = "1Gi"
}

# =============================================================================
# HIGH AVAILABILITY CONFIGURATION
# =============================================================================

variable "enable_ha" {
  description = "Enable high availability mode for TMM pods"
  type        = bool
  default     = true
}

variable "anti_affinity_enabled" {
  description = "Enable pod anti-affinity for TMM pods"
  type        = bool
  default     = true
}

# =============================================================================
# NETWORK CONFIGURATION
# =============================================================================

variable "network_attachments" {
  description = "Default network attachments for TMM pods"
  type = object({
    external = string
    internal = string
  })
  default = {
    external = "external-network"
    internal = "internal-network"
  }
}

# =============================================================================
# DEPENDENCY INPUTS
# =============================================================================

variable "flo_ready" {
  description = "Dependency flag indicating FLO is ready and CRDs are installed"
  type        = bool
}

# =============================================================================
# TAGS AND LABELS
# =============================================================================

variable "common_labels" {
  description = "Common labels to apply to all Kubernetes resources"
  type        = map(string)
  default     = {}
}
