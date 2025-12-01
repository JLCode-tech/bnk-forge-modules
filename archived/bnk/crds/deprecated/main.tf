# infrastructure-modules/spk-2.1/crds/deprecated/main.tf

# =============================================================================
# EKS CLUSTER DATA SOURCES
# =============================================================================

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# =============================================================================
# HELM RELEASE - DEPRECATED CRDS (FROM OCI REGISTRY)
# =============================================================================

resource "helm_release" "deprecated_crds" {
  count = var.install_deprecated_crds ? 1 : 0
  
  name       = "crd-deprecated"
  repository = "oci://repo.f5.com"
  chart      = "charts/f5-spk-crds-deprecated"
  version    = var.crd_deprecated_version
  namespace  = var.crd_conversion_namespace
  
  values = [
    yamlencode({
      conversion = {
        namespace = var.crd_conversion_namespace
      }
    })
  ]

  # Ensure service-proxy CRDs are installed first
  #depends_on = [var.service_proxy_crds_ready]

  # Ensure namespace exists before installing CRDs
  depends_on = [var.far_setup_complete]

  # Force update if version changes
  force_update = true
  
  # Timeout for CRD installation
  timeout = 300
}