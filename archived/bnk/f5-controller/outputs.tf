# infrastructure-modules/spk-2.1/f5-controller/outputs.tf

output "controller_release_name" {
  description = "Helm release name for F5 controller"
  value       = helm_release.f5_controller.name
}

output "controller_namespace" {
  description = "Namespace where F5 controller is deployed"
  value       = helm_release.f5_controller.namespace
}

output "controller_version" {
  description = "F5 controller chart version"
  value       = helm_release.f5_controller.version
}

output "external_vlan_names" {
  description = "Names of external VLAN CRs per AZ"
  value       = { for k, v in kubernetes_manifest.external_vlans : k => v.manifest.metadata.name }
}

output "internal_vlan_names" {
  description = "Names of internal VLAN CRs per AZ"
  value       = { for k, v in kubernetes_manifest.internal_vlans : k => v.manifest.metadata.name }
}