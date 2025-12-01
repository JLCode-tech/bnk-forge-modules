output "release_name" {
  description = "Helm release name"
  value       = helm_release.dssm.name
}

output "namespace" {
  description = "Namespace where dSSM is deployed"
  value       = helm_release.dssm.namespace
}

output "dssm_sentinel_service" {
  description = "dSSM Sentinel service name"
  value       = "f5-dssm-sentinel"
}

output "dssm_sentinel_host" {
  description = "dSSM Sentinel service hostname"
  value       = "f5-dssm-sentinel.${var.namespace}.svc.cluster.local"
}

output "dssm_sentinel_port" {
  description = "dSSM Sentinel service port"
  value       = 26379
}

output "dssm_db_service" {
  description = "dSSM DB service name"
  value       = "f5-dssm-db"
}

output "deployment_status" {
  description = "Deployment status"
  value       = helm_release.dssm.status
}