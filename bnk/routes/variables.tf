# infrastructure-modules/spk-2.1/routes/variables.tf
# Routes Module Variables - HTTPRoute, GRPCRoute, L4Route

# =============================================================================
# REQUIRED VARIABLES
# =============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for resource naming and identification)"
  type        = string
}

variable "route_name" {
  description = "Name of the route resource"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.route_name))
    error_message = "Route name must be valid Kubernetes resource name"
  }
}

variable "route_namespace" {
  description = "Namespace where route will be deployed"
  type        = string
}

variable "route_type" {
  description = "Type of route to create: HTTPRoute, GRPCRoute, or L4Route"
  type        = string

  validation {
    condition     = contains(["HTTPRoute", "GRPCRoute", "L4Route"], var.route_type)
    error_message = "Route type must be HTTPRoute, GRPCRoute, or L4Route"
  }
}

# =============================================================================
# PARENT REFS (GATEWAY ATTACHMENTS)
# =============================================================================

variable "parent_refs" {
  description = "List of parent Gateways this route attaches to"
  type = list(object({
    name        = string
    namespace   = optional(string)
    section_name = optional(string) # Listener name
    port        = optional(number)
  }))

  validation {
    condition     = length(var.parent_refs) > 0
    error_message = "At least one parent Gateway reference is required"
  }
}

# =============================================================================
# HOSTNAMES
# =============================================================================

variable "hostnames" {
  description = "List of hostnames for this route"
  type        = list(string)
  default     = []
}

# =============================================================================
# HTTP/GRPC ROUTE RULES
# =============================================================================

variable "rules" {
  description = "Routing rules for HTTPRoute or GRPCRoute"
  type = list(object({
    # Matches
    matches = optional(list(object({
      path = optional(object({
        type  = string # Exact, PathPrefix, RegularExpression
        value = string
      }))
      headers = optional(list(object({
        type  = string # Exact, RegularExpression
        name  = string
        value = string
      })))
      query_params = optional(list(object({
        type  = string # Exact, RegularExpression
        name  = string
        value = string
      })))
      method = optional(string) # GET, POST, etc.
    })))

    # Filters
    filters = optional(list(object({
      type = string # RequestHeaderModifier, ResponseHeaderModifier, RequestRedirect, URLRewrite

      # RequestHeaderModifier / ResponseHeaderModifier
      request_header_modifier = optional(object({
        set    = optional(list(object({ name = string, value = string })))
        add    = optional(list(object({ name = string, value = string })))
        remove = optional(list(string))
      }))

      response_header_modifier = optional(object({
        set    = optional(list(object({ name = string, value = string })))
        add    = optional(list(object({ name = string, value = string })))
        remove = optional(list(string))
      }))

      # RequestRedirect
      request_redirect = optional(object({
        scheme      = optional(string)
        hostname    = optional(string)
        path        = optional(object({ type = string, replace_full_path = optional(string), replace_prefix_match = optional(string) }))
        port        = optional(number)
        status_code = optional(number)
      }))

      # URLRewrite
      url_rewrite = optional(object({
        hostname = optional(string)
        path     = optional(object({ type = string, replace_full_path = optional(string), replace_prefix_match = optional(string) }))
      }))
    })))

    # Backend refs
    backend_refs = optional(list(object({
      name      = string
      namespace = optional(string)
      port      = optional(number)
      weight    = optional(number)
      kind      = optional(string) # Service (default), or custom
      group     = optional(string)
    })))

    # Timeouts
    timeouts = optional(object({
      request         = optional(string) # Duration like "30s"
      backend_request = optional(string)
    }))
  }))
  default = []
}

# =============================================================================
# L4 ROUTE CONFIGURATION (for L4Route)
# =============================================================================

variable "l4_backend_refs" {
  description = "Backend references for L4Route"
  type = list(object({
    name      = string
    namespace = optional(string)
    port      = number
    weight    = optional(number)
  }))
  default = []
}

variable "l4_protocol" {
  description = "Protocol for L4Route (TCP or UDP)"
  type        = string
  default     = "TCP"

  validation {
    condition     = contains(["TCP", "UDP"], var.l4_protocol)
    error_message = "L4 protocol must be TCP or UDP"
  }
}

# =============================================================================
# SESSION AFFINITY (L4Route)
# =============================================================================

variable "session_affinity" {
  description = "Session affinity configuration for L4Route"
  type = object({
    enabled     = bool
    timeout     = optional(string) # Duration like "3600s"
    cookie_name = optional(string)
  })
  default = null
}

# =============================================================================
# DEPENDENCY INPUTS
# =============================================================================

variable "gateway_ready" {
  description = "Dependency flag indicating Gateway is ready"
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
  description = "Annotations to add to the route resource"
  type        = map(string)
  default     = {}
}
