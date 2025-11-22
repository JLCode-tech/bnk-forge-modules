# infrastructure-modules/spk-2.1/bnk-gatewayclass/outputs.tf

output "gatewayclass_name" {
  description = "Name of the BNKGatewayClass"
  value       = kubernetes_manifest.bnk_gatewayclass.manifest.metadata.name
}

output "gatewayclass_controller" {
  description = "Controller name for the GatewayClass"
  value       = var.controller_name
}

output "gatewayclass_ready" {
  description = "Flag indicating BNKGatewayClass is ready"
  value       = true
  depends_on  = [null_resource.verify_gatewayclass]
}

output "config_name" {
  description = "Name of the BNKGatewayClassConfig"
  value       = kubernetes_manifest.bnk_gatewayclass_config.manifest.metadata.name
}

output "default_tmm_replicas" {
  description = "Default TMM replica count configured"
  value       = var.default_tmm_replicas
}

output "ipam_enabled" {
  description = "Whether IPAM is enabled for this GatewayClass"
  value       = var.enable_ipam
}
