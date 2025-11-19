# infrastructure-modules/spk-2.1/network-setup/outputs.tf

output "internal_nad_name" {
  description = "Name of the internal network attachment definition"
  value       = "internal-netdevice"
}

output "external_nad_name" {
  description = "Name of the external network attachment definition"
  value       = "external-netdevice"
}

output "namespace" {
  description = "Namespace where NADs are deployed"
  value       = var.namespace
}