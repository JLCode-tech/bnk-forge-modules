# k8s/cert-manager/variables.tf
# Jetstack cert-manager Module Variables
# Per F5 BNK 2.2 GA: Use Jetstack cert-manager v1.16.1

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
# CLUSTER CONFIGURATION
# =============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for resource naming and identification)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for cert-manager deployment"
  type        = string
  default     = "cert-manager"
}

variable "create_namespace" {
  description = "Whether to create the namespace (set to false if namespace already exists)"
  type        = bool
  default     = true
}

# =============================================================================
# CERT-MANAGER VERSION
# =============================================================================

variable "cert_manager_version" {
  description = "Version of Jetstack cert-manager to deploy. F5 BNK 2.4.1 GA tested with v1.16.2"
  type        = string
  default     = "v1.16.2"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+", var.cert_manager_version))
    error_message = "The cert_manager_version must be a valid semantic version (e.g., v1.16.2)."
  }
}

variable "release_name" {
  description = "Helm release name for cert-manager"
  type        = string
  default     = "cert-manager"
}

# =============================================================================
# CLUSTER ISSUER CONFIGURATION
# =============================================================================

variable "create_cluster_issuer" {
  description = "Whether to create the self-signed ClusterIssuer for BNK certificates"
  type        = bool
  default     = true
}

variable "cluster_issuer_name" {
  description = "Name of the CA ClusterIssuer (referenced by FLO and CNEInstance)"
  type        = string
  default     = "bnk-ca-cluster-issuer"
}

variable "ca_certificate_name" {
  description = "Name of the CA certificate and secret"
  type        = string
  default     = "bnk-ca"
}

# =============================================================================
# REPLICA CONFIGURATION
# =============================================================================

variable "controller_replicas" {
  description = "Number of cert-manager controller replicas"
  type        = number
  default     = 1
}

variable "webhook_replicas" {
  description = "Number of cert-manager webhook replicas"
  type        = number
  default     = 1
}

variable "cainjector_replicas" {
  description = "Number of cert-manager cainjector replicas"
  type        = number
  default     = 1
}

# =============================================================================
# RESOURCE CONFIGURATION
# =============================================================================

variable "resources" {
  description = "Resource requests and limits for cert-manager components (set to null to use defaults)"
  type        = any
  default     = null
}

variable "helm_timeout" {
  description = "Timeout in seconds for Helm operations"
  type        = number
  default     = 600
}

# =============================================================================
# BNK CERTIFICATE CONFIGURATION
# =============================================================================
# These variables control the creation of BNK-specific certificates using
# cert-manager Certificate CRDs. This replaces the old f5-cert-gen approach
# with fully managed, auto-rotating certificates.

variable "bnk_namespace" {
  description = "Namespace where BNK components are deployed (OTEL certs are created here — must match CNEInstance namespace)"
  type        = string
  default     = "f5-operator"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.bnk_namespace))
    error_message = "Namespace must be a valid Kubernetes namespace name"
  }
}

variable "create_otel_certs" {
  description = "Create OTEL telemetry certificates via cert-manager. Replaces the static Helm-embedded cert from FLO with a managed, auto-rotating one. NOTE: CWC certs are NOT needed here — FLO auto-creates those as cert-manager Certificate CRDs (tls-spkcwc-*, tls-csmqkview-*, etc.)."
  type        = bool
  default     = true
}


