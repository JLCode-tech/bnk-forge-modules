# infrastructure-modules/spk-2.1/crds/service-proxy/outputs.tf

output "release_name" {
  description = "Helm release name for service-proxy CRDs"
  value       = helm_release.service_proxy_crds.name
}

output "release_status" {
  description = "Status of service-proxy CRDs Helm release"
  value       = helm_release.service_proxy_crds.status
}

output "release_version" {
  description = "Version of installed service-proxy CRDs"
  value       = helm_release.service_proxy_crds.version
}

output "chart_version" {
  description = "Service-proxy CRDs bundle version"
  value       = var.crd_service_proxy_version
}

output "installed_crds" {
  description = "List of installed service-proxy CRDs"
  value = [
    "f5-spk-egresses.k8s.f5net.com",
    "f5-spk-ingressdiameters.k8s.f5net.com",
    "f5-spk-ingressgtps.k8s.f5net.com",
    "f5-spk-ingresshttp2s.k8s.f5net.com",
    "f5-spk-ingressngaps.k8s.f5net.com",
    "f5-spk-ingresstcps.ingresstcp.k8s.f5net.com",
    "f5-spk-ingressudps.ingressudp.k8s.f5net.com"
  ]
}

output "service_proxy_crds_ready" {
  description = "Boolean indicating service-proxy CRDs are installed"
  value       = helm_release.service_proxy_crds.status == "deployed"
}