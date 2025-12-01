# infrastructure-modules/spk-2.1/crds/service-proxy/variables.tf

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for resource naming and identification)"
  type        = string
}

variable "crd_service_proxy_version" {
  description = "Version of service-proxy CRDs Helm chart"
  type        = string
}

variable "crd_conversion_namespace" {
  description = "Namespace for CRD conversion webhook"
  type        = string
  default     = "f5-utils"
}

variable "far_setup_complete" {
  description = "Dependency flag from far-setup module"
  type        = bool
}