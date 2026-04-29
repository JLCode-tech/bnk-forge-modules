# k8s/bnk-prerequisites/outputs.tf
# BNK Prerequisites Module Outputs

# =============================================================================
# NAMESPACE OUTPUTS
# =============================================================================

output "cne_core_namespace" {
  description = "CNE core namespace (FLO, CWC, IPAM, Observer)"
  value       = kubernetes_namespace_v1.cne_core.metadata[0].name
}

output "cne_instance_namespace" {
  description = "CNE instance namespace (TMM, VLANs, NADs, controller)"
  value       = kubernetes_namespace_v1.cne_instance.metadata[0].name
}

# =============================================================================
# FAR SECRET OUTPUTS
# =============================================================================

output "far_secret_name" {
  description = "Name of the FAR image pull secret (always 'far-secret')"
  value       = "far-secret"
}

# =============================================================================
# VERSION OUTPUTS (from manifest parsing)
# =============================================================================

output "flo_version" {
  description = "FLO Helm chart version parsed from manifest"
  value       = lookup(data.external.component_versions.result, "flo", "")
}

output "manifest_version" {
  description = "BNK manifest version used"
  value       = var.bnk_manifest_version
}

output "component_versions" {
  description = "All component versions parsed from manifest"
  value       = data.external.component_versions.result
}

output "cert_manager_version" {
  description = "F5 cert-manager version from manifest (informational — cert-manager module uses its own version)"
  value       = lookup(data.external.component_versions.result, "cert_manager", "")
}

# =============================================================================
# DEPENDENCY GATE
# =============================================================================

output "prerequisites_ready" {
  description = "Boolean gate — true when namespaces, secrets, and manifest are all ready"
  value       = true

  depends_on = [
    kubernetes_namespace_v1.cne_core,
    kubernetes_namespace_v1.cne_instance,
    kubernetes_secret_v1.far_secret_cne_core,
    kubernetes_secret_v1.far_secret_cne_instance,
    data.external.component_versions,
  ]
}
