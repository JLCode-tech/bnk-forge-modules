variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for resource naming and identification)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for CWC and RabbitMQ"
  type        = string
}

variable "far_secret_name" {
  description = "Name of the FAR pull secret"
  type        = string
}

variable "cwc_version" {
  description = "Version of CWC chart"
  type        = string
}

variable "rabbitmq_version" {
  description = "Version of RabbitMQ chart"
  type        = string
}

variable "image_registry" {
  description = "F5 image registry"
  type        = string
  default     = "repo.f5.com/images"
}

variable "storage_class" {
  description = "Storage class for persistence"
  type        = string
}

variable "node_selector" {
  description = "Node selector for pod placement"
  type        = map(string)
  default     = {}
}

variable "connected_mode" {
  description = "Enable connected mode for automatic licensing"
  type        = bool
}

variable "license_environment" {
  description = "Licensing environment: production or test"
  type        = string
  
  validation {
    condition     = contains(["production", "test"], var.license_environment)
    error_message = "license_environment must be either 'production' or 'test'"
  }
}

variable "jwt_token" {
  description = "JWT token for licensing"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cert_manager_ready" {
  description = "Dependency on cert-manager"
  type        = bool
}