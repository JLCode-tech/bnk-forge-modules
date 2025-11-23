variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for resource naming and identification)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for cert-manager (from far-setup outputs)"
  type        = string
}

variable "far_secret_name" {
  description = "Name of the FAR pull secret (from far-setup outputs)"
  type        = string
}

variable "cert_manager_version" {
  description = "Version of f5-cert-manager chart (from far-setup outputs)"
  type        = string
}

variable "image_registry" {
  description = "F5 image registry for cert-manager components"
  type        = string
  default     = "repo.f5.com"
}

variable "release_name" {
  description = "Helm release name for cert-manager"
  type        = string
  default     = "f5-cert-manager"
}