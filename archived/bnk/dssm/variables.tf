variable "release_name" {
  description = "Helm release name for dSSM"
  type        = string
}

variable "namespace" {
  description = "Namespace for dSSM deployment"
  type        = string
}

variable "dssm_version" {
  description = "Version of dSSM helm chart"
  type        = string
}

variable "image_registry" {
  description = "Docker registry URL for F5 images"
  type        = string
}

variable "far_secret_name" {
  description = "Name of the FAR registry secret"
  type        = string
}

variable "replica_count" {
  description = "Number of Sentinel and DB replicas"
  type        = number
  default     = 3
}

variable "storage_class" {
  description = "Storage class for dSSM persistent volumes"
  type        = string
}

variable "persistent_storage_gb" {
  description = "Storage size in GB per DB pod"
  type        = number
  default     = 1
}

variable "access_mode" {
  description = "Access mode for persistent volumes"
  type        = string
  default     = "ReadWriteOnce"
}

variable "affinity_type" {
  description = "Pod affinity type (required/preferred/custom)"
  type        = string
  default     = "required"
}

variable "pod_disruption_min" {
  description = "Minimum pods available during disruption"
  type        = number
  default     = 2
}

variable "sentinel_cpu_request" {
  description = "CPU request for Sentinel pods"
  type        = string
  default     = "0.5"
}

variable "sentinel_memory_request" {
  description = "Memory request for Sentinel pods"
  type        = string
  default     = "128Mi"
}

variable "db_cpu_request" {
  description = "CPU request for DB pods"
  type        = string
  default     = "1"
}

variable "db_memory_request" {
  description = "Memory request for DB pods"
  type        = string
  default     = "512Mi"
}

variable "fluentd_host" {
  description = "Fluentd service hostname for logging"
  type        = string
}

variable "fluentd_port" {
  description = "Fluentd service port"
  type        = number
  default     = 54321
}

variable "dependencies" {
  description = "List of resource dependencies"
  type        = list(any)
  default     = []
}