# infrastructure-modules/spk-2.1/network-setup/variables.tf

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for resource naming and identification)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for network resources"
  type        = string
}

variable "external_subnet_cidrs" {
  description = "List of external subnet CIDRs for IPAM ranges (one per AZ)"
  type        = list(string)
}

variable "internal_subnet_cidrs" {
  description = "List of internal subnet CIDRs for IPAM ranges (one per AZ)"
  type        = list(string)
}

variable "crds_ready" {
  description = "Dependency flag to ensure CRDs are ready"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}