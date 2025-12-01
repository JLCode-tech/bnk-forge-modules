# infrastructure-modules/spk-2.1/crds/service-proxy/main.tf

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
# HELM RELEASE - SERVICE PROXY CRDS (FROM OCI REGISTRY)
# =============================================================================

resource "helm_release" "service_proxy_crds" {
  name       = "crd-proxy"
  repository = "oci://repo.f5.com"
  chart      = "charts/f5-spk-crds-service-proxy"
  version    = var.crd_service_proxy_version
  namespace  = var.crd_conversion_namespace
  
  values = [
    yamlencode({
      conversion = {
        namespace = var.crd_conversion_namespace
      }
    })
  ]

  # Ensure common CRDs are installed first
  #depends_on = [var.common_crds_ready]

  # Ensure namespace exists before installing CRDs
  depends_on = [var.far_setup_complete]

  # Force update if version changes
  force_update = true
  
  # Timeout for CRD installation
  timeout = 300
}