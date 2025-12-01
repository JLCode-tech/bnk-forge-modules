# infrastructure-modules/spk-2.1/crds/deprecated/outputs.tf

output "release_name" {
  description = "Helm release name for deprecated CRDs"
  value       = var.install_deprecated_crds ? helm_release.deprecated_crds[0].name : null
}

output "release_status" {
  description = "Status of deprecated CRDs Helm release"
  value       = var.install_deprecated_crds ? helm_release.deprecated_crds[0].status : "skipped"
}

output "release_version" {
  description = "Version of installed deprecated CRDs"
  value       = var.install_deprecated_crds ? helm_release.deprecated_crds[0].version : null
}

output "chart_version" {
  description = "Deprecated CRDs bundle version"
  value       = var.crd_deprecated_version
}

output "deprecated_crds_ready" {
  description = "Boolean indicating deprecated CRDs are installed or skipped"
  value       = var.install_deprecated_crds ? (helm_release.deprecated_crds[0].status == "deployed") : true
}

output "installation_skipped" {
  description = "Whether deprecated CRDs installation was skipped"
  value       = !var.install_deprecated_crds
}