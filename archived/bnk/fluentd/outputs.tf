# infrastructure-modules/spk-2.1/fluentd/outputs.tf

# =============================================================================
# FLUENTD SERVICE OUTPUTS
# =============================================================================

output "fluentd_host" {
  description = "Fluentd service hostname for SPK components to send logs"
  value       = "${var.release_name}.${var.namespace}.svc.cluster.local"
}

output "fluentd_port" {
  description = "Fluentd service port for log ingestion"
  value       = "54321"
}

output "service_name" {
  description = "Kubernetes service name for Fluentd"
  value       = var.release_name
}

# =============================================================================
# DEPLOYMENT STATUS
# =============================================================================

output "deployment_complete" {
  description = "Flag indicating Fluentd deployment is complete"
  value       = true
  depends_on  = [helm_release.fluentd]
}

output "namespace" {
  description = "Namespace where Fluentd is deployed"
  value       = var.namespace
}

output "helm_release_name" {
  description = "Helm release name for Fluentd"
  value       = helm_release.fluentd.name
}

output "helm_release_version" {
  description = "Deployed Helm chart version"
  value       = helm_release.fluentd.version
}