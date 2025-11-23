# infrastructure-modules/spk-2.1/bnk-netpolicy/variables.tf
# BNKNetPolicy Module Variables - Network Policies and Extensions

# =============================================================================
# REQUIRED VARIABLES
# =============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for resource naming and identification)"
  type        = string
}

variable "policy_name" {
  description = "Name of the BNKNetPolicy resource"
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
# IRULES CONFIGURATION
# =============================================================================

variable "irules" {
  description = "List of iRule references or inline iRule definitions"
  type = list(object({
    name      = optional(string) # Reference to existing iRule
    namespace = optional(string)
    inline    = optional(string) # Inline iRule TCL code
  }))
  default = []
}

# =============================================================================
# TCP SETTINGS
# =============================================================================

variable "tcp_profile" {
  description = "TCP profile configuration"
  type = object({
    idle_timeout           = optional(string) # Duration like "300s"
    close_wait_timeout     = optional(string)
    fin_wait_timeout       = optional(string)
    keep_alive_interval    = optional(string)
    tcp_window_size        = optional(number)
    nagle_algorithm        = optional(bool)
    delayed_acks           = optional(bool)
    reset_on_timeout       = optional(bool)
    proxy_buffer_low       = optional(number)
    proxy_buffer_high      = optional(number)
  })
  default = null
}

variable "tcp_settings_ref" {
  description = "Reference to existing F5 TCP settings profile"
  type = object({
    name      = string
    namespace = optional(string)
  })
  default = null
}

# =============================================================================
# HTTP/HTTPS SETTINGS
# =============================================================================

variable "http_profile" {
  description = "HTTP profile configuration"
  type = object({
    xff_enabled        = optional(bool)   # X-Forwarded-For
    xff_trusted_proxies = optional(list(string))
    max_header_size    = optional(number)
    max_headers_count  = optional(number)
    request_chunking   = optional(string) # preserve, selective, rechunk
    response_chunking  = optional(string)
    pipeline_mode      = optional(string) # reject, pasthrough, controlled
  })
  default = null
}

# =============================================================================
# HSL LOGGING (HIGH-SPEED LOGGING)
# =============================================================================

variable "hsl_logging" {
  description = "High-speed logging configuration"
  type = object({
    enabled     = bool
    publisher_ref = optional(object({
      name      = string
      namespace = optional(string)
    }))
    log_profile_ref = optional(object({
      name      = string
      namespace = optional(string)
    }))
    # Logging format and filters
    log_format = optional(string) # json, key-value, etc.
    log_level  = optional(string) # debug, info, warning, error
  })
  default = null
}

# =============================================================================
# CONNECTION POOLING
# =============================================================================

variable "connection_pool" {
  description = "Backend connection pooling configuration"
  type = object({
    max_connections         = optional(number)
    max_idle_connections    = optional(number)
    idle_timeout            = optional(string)
    connection_timeout      = optional(string)
    max_requests_per_conn   = optional(number)
  })
  default = null
}

# =============================================================================
# PERSISTENCE/SESSION AFFINITY
# =============================================================================

variable "persistence" {
  description = "Session persistence configuration"
  type = object({
    type     = string # cookie, source-ip, hash
    timeout  = optional(string)
    # Cookie persistence
    cookie_name     = optional(string)
    cookie_method   = optional(string) # insert, rewrite, passive
    cookie_encrypt  = optional(bool)
    # Hash persistence
    hash_algorithm  = optional(string)
  })
  default = null
}

# =============================================================================
# SSL/TLS SETTINGS
# =============================================================================

variable "ssl_profile" {
  description = "SSL/TLS profile configuration for backend connections"
  type = object({
    enabled            = bool
    cipher_suite       = optional(string)
    min_protocol       = optional(string) # TLSv1.2, TLSv1.3
    max_protocol       = optional(string)
    verify_server_cert = optional(bool)
    ca_bundle_ref      = optional(object({
      name      = string
      namespace = optional(string)
    }))
  })
  default = null
}

# =============================================================================
# COMPRESSION
# =============================================================================

variable "compression" {
  description = "HTTP compression configuration"
  type = object({
    enabled           = bool
    algorithms        = optional(list(string)) # gzip, deflate, br
    min_size          = optional(number)       # Minimum bytes to compress
    content_types     = optional(list(string)) # MIME types to compress
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
