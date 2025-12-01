# infrastructure-modules/spk-2.1/crds/deprecated/variables.tf

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for resource naming and identification)"
  type        = string
}

variable "crd_deprecated_version" {
  description = "Version of deprecated CRDs Helm chart"
  type        = string
}

variable "crd_conversion_namespace" {
  description = "Namespace for CRD conversion webhook"
  type        = string
  default     = "f5-utils"
}

variable "install_deprecated_crds" {
  description = "Whether to install deprecated CRDs bundle"
  type        = bool
  default     = true
}

variable "far_setup_complete" {
  description = "Dependency flag from far-setup module"
  type        = bool
}