variable "cluster_name" {
  description = "Name identifier for this OCP cluster"
  type        = string
}

variable "api_server_url" {
  description = "OpenShift API server URL (e.g., https://api.cluster.example.com:6443)"
  type        = string
}

variable "kubeconfig_content" {
  description = "Kubeconfig YAML content for the OCP cluster. Automatically superseded by the project's registered-cluster kubeconfig (local.forge_kubeconfig) when one exists; this variable is only used when no registered cluster is present, e.g. standalone or manual runs."
  type        = string
  sensitive   = true
  default     = ""
}

variable "oc_token" {
  description = "OpenShift token (alternative to kubeconfig)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "skip_tls_verify" {
  description = "Skip TLS certificate verification (use only for self-signed certs in dev/test)"
  type        = bool
  default     = false
}
