# infrastructure-modules/spk-2.1/bnk-netpolicy/outputs.tf

output "policy_name" {
  description = "Name of the BNKNetPolicy resource"
  value       = kubernetes_manifest.bnk_netpolicy.manifest.metadata.name
}

output "policy_namespace" {
  description = "Namespace where policy is deployed"
  value       = kubernetes_manifest.bnk_netpolicy.manifest.metadata.namespace
}

output "policy_ready" {
  description = "Flag indicating policy is ready"
  value       = true
  depends_on  = [null_resource.verify_policy]
}

output "irules_count" {
  description = "Number of iRules configured"
  value       = length(var.irules)
}

output "tcp_profile_configured" {
  description = "Whether TCP profile is configured"
  value       = var.tcp_profile != null || var.tcp_settings_ref != null
}

output "http_profile_configured" {
  description = "Whether HTTP profile is configured"
  value       = var.http_profile != null
}

output "logging_enabled" {
  description = "Whether HSL logging is enabled"
  value       = var.hsl_logging != null ? var.hsl_logging.enabled : false
}
