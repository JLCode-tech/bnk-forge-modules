# infrastructure-modules/spk-2.1/bnk-secpolicy/outputs.tf

output "policy_name" {
  description = "Name of the BNKSecPolicy resource"
  value       = kubernetes_manifest.bnk_secpolicy.manifest.metadata.name
}

output "policy_namespace" {
  description = "Namespace where policy is deployed"
  value       = kubernetes_manifest.bnk_secpolicy.manifest.metadata.namespace
}

output "policy_ready" {
  description = "Flag indicating policy is ready"
  value       = true
  depends_on  = [null_resource.verify_policy]
}

output "firewall_enabled" {
  description = "Whether firewall is enabled"
  value       = var.enable_firewall
}

output "ddos_enabled" {
  description = "Whether DDoS protection is enabled"
  value       = var.enable_ddos
}

output "rate_limiting_enabled" {
  description = "Whether rate limiting is enabled"
  value       = var.enable_rate_limiting
}
