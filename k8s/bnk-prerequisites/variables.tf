# k8s/bnk-prerequisites/variables.tf
# BNK Prerequisites Module Variables

# =============================================================================
# PLATFORM KUBECONFIG (injected by BNK-Forge or set manually)
# =============================================================================

variable "forge_kubeconfig_content" {
  description = "Kubeconfig YAML content. Automatically injected by BNK-Forge for any platform (EKS, AKS, GKE, OCP, generic). Set manually for standalone usage."
  type        = string
  default     = ""
  sensitive   = true
}

# =============================================================================
# REQUIRED — Injected as Project Secret
# =============================================================================

variable "cne_pull_secret" {
  description = <<-EOT
    F5 FAR registry credentials. Accepts TWO formats:
    Format A: Base64-encoded JSON service account key from F5 (bare key).
    Format B: Base64-encoded dockerconfigjson ({"auths":{"repo.f5.com":{"auth":"..."}}}).
    Both are auto-detected. Injected as a project secret.
  EOT
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.cne_pull_secret) > 0
    error_message = "cne_pull_secret must not be empty. Configure it as a project secret."
  }
}

# =============================================================================
# NAMESPACE CONFIGURATION
# =============================================================================

variable "cne_core_namespace" {
  description = "Namespace for FLO operator and CNE core components (CWC, IPAM, RabbitMQ, Observer, OTEL). Per F5 BNK 2.2 docs: f5-cne-core."
  type        = string
  default     = "f5-cne-core"
}

variable "cne_instance_namespace" {
  description = "Namespace for CNEInstance workloads (TMM, CNE controller, VLANs, NADs). Configurable per deployment."
  type        = string
  default     = "f5-bnk"
}

# =============================================================================
# BNK MANIFEST VERSION
# =============================================================================

variable "bnk_manifest_version" {
  description = "BNK manifest version to download from FAR (e.g., 2.2.1-3.2226.0-0.0.511)"
  type        = string
  default     = "2.2.1-3.2226.0-0.0.511"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+-", var.bnk_manifest_version))
    error_message = "BNK manifest version must start with X.Y.Z- format"
  }
}

# =============================================================================
# CLUSTER IDENTIFICATION (auto-wired)
# =============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (auto-wired from EKS module)"
  type        = string
  default     = ""
}
