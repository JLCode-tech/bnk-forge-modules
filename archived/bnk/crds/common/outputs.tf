# infrastructure-modules/spk-2.1/crds/common/outputs.tf

output "release_name" {
  description = "Helm release name for common CRDs"
  value       = helm_release.common_crds.name
}

output "release_status" {
  description = "Status of common CRDs Helm release"
  value       = helm_release.common_crds.status
}

output "release_version" {
  description = "Version of installed common CRDs"
  value       = helm_release.common_crds.version
}

output "chart_version" {
  description = "Common CRDs bundle version"
  value       = var.crd_common_version
}

output "installed_crds" {
  description = "List of installed common CRDs"
  value = [
    "f5-spk-addresslists.k8s.f5net.com",
    "f5-spk-dnscaches.k8s.f5net.com",
    "f5-spk-portlists.k8s.f5net.com",
    "f5-spk-snatpools.k8s.f5net.com",
    "f5-spk-staticroutes.k8s.f5net.com",
    "f5-spk-vlans.k8s.f5net.com",
    "network-attachment-definitions.k8s.cni.cncf.io"
  ]
}

output "nad_crd_name" {
  description = "Name of Network Attachment Definition CRD"
  value       = "network-attachment-definitions.k8s.cni.cncf.io"
}

output "common_crds_ready" {
  description = "Boolean indicating common CRDs are installed"
  value       = helm_release.common_crds.status == "deployed"
}