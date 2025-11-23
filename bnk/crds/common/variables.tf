# infrastructure-modules/spk-2.1/crds/common/variables.tf

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for resource naming and identification)"
  type        = string
}

variable "crd_common_version" {
  description = "Version of common CRDs Helm chart"
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