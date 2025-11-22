# infrastructure-modules/spk-2.1/gateway/outputs.tf

output "gateway_name" {
  description = "Name of the Gateway resource"
  value       = kubernetes_manifest.gateway.manifest.metadata.name
}

output "gateway_namespace" {
  description = "Namespace where Gateway is deployed"
  value       = kubernetes_manifest.gateway.manifest.metadata.namespace
}

output "gateway_ready" {
  description = "Flag indicating Gateway is ready for routes"
  value       = true
  depends_on  = [null_resource.verify_gateway]
}

output "listeners" {
  description = "List of configured listeners"
  value = [
    for listener in var.listeners : {
      name     = listener.name
      protocol = listener.protocol
      port     = listener.port
    }
  ]
}

output "security_policies_attached" {
  description = "Number of security policies attached"
  value       = length(var.security_policy_refs)
}

output "network_policies_attached" {
  description = "Number of network policies attached"
  value       = length(var.network_policy_refs)
}
