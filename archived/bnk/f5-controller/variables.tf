# infrastructure-modules/spk-2.1/f5-controller/variables.tf

# ========================================================================
# CLUSTER CONFIGURATION
# ========================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for resource naming and identification)"
  type        = string
}

# ========================================================================
# NAMESPACE CONFIGURATION
# ========================================================================

variable "f5_spk_namespace" {
  description = "Namespace for F5 SPK controller and TMM pods"
  type        = string
}

variable "rabbitmq_namespace" {
  description = "RabbitMQ namespace (typically f5-utils)"
  type        = string
}

# ========================================================================
# REGISTRY AND VERSIONS
# ========================================================================

variable "f5_image_registry" {
  description = "F5 image registry URL"
  type        = string
}

variable "f5_controller_chart_version" {
  description = "F5 ingress controller chart version"
  type        = string
}

variable "far_secret_name" {
  description = "Name of the FAR pull secret"
  type        = string
}

# ========================================================================
# NETWORK CONFIGURATION
# ========================================================================

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "external_nad_name" {
  description = "Name of the external network attachment definition"
  type        = string
}

variable "internal_nad_name" {
  description = "Name of the internal network attachment definition"
  type        = string
}

variable "f5_global_mtu" {
  description = "Global MTU size for TMM interfaces"
  type        = number
}

variable "f5_vlan_mtu" {
  description = "VLAN MTU size for TMM interfaces"
  type        = number
}

variable "f5_vlan_ips" {
  description = "VLAN IP configuration per AZ"
  type = map(object({
    external_ip     = string
    external_prefix = number
    internal_ip     = string
    internal_prefix = number
  }))
}

# ========================================================================
# SERVICE DEPENDENCIES
# ========================================================================

variable "dssm_sentinel_host" {
  description = "dSSM Sentinel service host"
  type        = string
}

variable "dssm_sentinel_port" {
  description = "dSSM Sentinel service port"
  type        = number
}

# ========================================================================
# TMM RESOURCE CONFIGURATION
# ========================================================================

variable "f5_tmm_cpu_cores" {
  description = "Number of CPU cores for TMM"
  type        = number
}

variable "f5_tmm_memory" {
  description = "Memory allocation for TMM"
  type        = string
}

variable "f5_tmm_hugepages_2mi" {
  description = "Hugepages 2Mi allocation for TMM"
  type        = string
}

# ========================================================================
# COMMON TAGS
# ========================================================================

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}