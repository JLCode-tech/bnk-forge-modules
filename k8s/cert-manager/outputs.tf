output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.cert_manager.name
}

output "release_status" {
  description = "Status of the Helm release"
  value       = helm_release.cert_manager.status
}

output "namespace" {
  description = "Namespace where cert-manager is deployed"
  value       = helm_release.cert_manager.namespace
}

output "chart_version" {
  description = "Version of the deployed cert-manager chart"
  value       = helm_release.cert_manager.version
}

output "cert_manager_ready" {
  description = "Indicates cert-manager deployment is complete"
  value       = true
  depends_on  = [helm_release.cert_manager]
}