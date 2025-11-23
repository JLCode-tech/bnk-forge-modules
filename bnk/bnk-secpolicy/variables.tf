# infrastructure-modules/spk-2.1/bnk-secpolicy/variables.tf
# BNKSecPolicy Module Variables - Security Policies for Gateways

# =============================================================================
# REQUIRED VARIABLES
# =============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for resource naming and identification)"
  type        = string
}

variable "policy_name" {
  description = "Name of the BNKSecPolicy resource"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.policy_name))
    error_message = "Policy name must be valid Kubernetes resource name"
  }
}

variable "policy_namespace" {
  description = "Namespace where policy will be deployed"
  type        = string
}

# =============================================================================
# FIREWALL POLICY CONFIGURATION
# =============================================================================

variable "enable_firewall" {
  description = "Enable firewall policy"
  type        = bool
  default     = false
}

variable "firewall_policy_ref" {
  description = "Reference to F5BigFwPolicy resource"
  type = object({
    name      = string
    namespace = optional(string)
  })
  default = null
}

variable "firewall_rule_lists" {
  description = "List of firewall rule list references"
  type = list(object({
    name      = string
    namespace = optional(string)
  }))
  default = []
}

# =============================================================================
# DDOS PROTECTION
# =============================================================================

variable "enable_ddos" {
  description = "Enable DDoS protection"
  type        = bool
  default     = false
}

variable "ddos_global_ref" {
  description = "Reference to F5BigDdosGlobal resource"
  type = object({
    name      = string
    namespace = optional(string)
  })
  default = null
}

variable "ddos_protection_mode" {
  description = "DDoS protection mode"
  type        = string
  default     = "auto"

  validation {
    condition     = contains(["auto", "manual", "off"], var.ddos_protection_mode)
    error_message = "DDoS protection mode must be auto, manual, or off"
  }
}

# =============================================================================
# ACCESS CONTROL
# =============================================================================

variable "allowed_source_ranges" {
  description = "List of allowed source IP CIDR ranges"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.allowed_source_ranges :
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", cidr))
    ])
    error_message = "All source ranges must be valid CIDR notation"
  }
}

variable "denied_source_ranges" {
  description = "List of denied source IP CIDR ranges"
  type        = list(string)
  default     = []
}

variable "address_lists" {
  description = "References to F5BigCneAddresslist resources"
  type = list(object({
    name      = string
    namespace = optional(string)
    action    = string # allow or deny
  }))
  default = []
}

# =============================================================================
# RATE LIMITING
# =============================================================================

variable "enable_rate_limiting" {
  description = "Enable rate limiting"
  type        = bool
  default     = false
}

variable "rate_limit_config" {
  description = "Rate limiting configuration"
  type = object({
    requests_per_second = number
    burst_size          = optional(number)
    key                 = optional(string) # remote_address, header, etc.
  })
  default = null
}

# =============================================================================
# LOGGING
# =============================================================================

variable "log_profile_ref" {
  description = "Reference to F5BigLogProfile for security logging"
  type = object({
    name      = string
    namespace = optional(string)
  })
  default = null
}

variable "hsl_publisher_ref" {
  description = "Reference to F5BigLogHslpub for remote logging"
  type = object({
    name      = string
    namespace = optional(string)
  })
  default = null
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

variable "annotations" {
  description = "Annotations to add to the policy resource"
  type        = map(string)
  default     = {}
}
