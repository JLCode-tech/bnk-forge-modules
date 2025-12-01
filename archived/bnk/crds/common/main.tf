# infrastructure-modules/spk-2.1/crds/common/main.tf

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
# HELM RELEASE - COMMON CRDS (FROM OCI REGISTRY)
# =============================================================================

resource "helm_release" "common_crds" {
  name       = "crd-common"
  repository = "oci://repo.f5.com"
  chart      = "charts/f5-spk-crds-common"
  version    = var.crd_common_version
  namespace  = var.crd_conversion_namespace

  values = [
    yamlencode({
      conversion = {
        namespace = var.crd_conversion_namespace
      }
    })
  ]

  # Ensure namespace exists before installing CRDs
  depends_on = [var.far_setup_complete]

  # Force update if version changes
  force_update = true
  
  # Timeout for CRD installation
  timeout = 300
}

# =============================================================================
# NETWORK ATTACHMENT DEFINITION CRD (MULTUS)
# =============================================================================

resource "kubernetes_manifest" "nad_crd" {
  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "network-attachment-definitions.k8s.cni.cncf.io"
    }
    spec = {
      group = "k8s.cni.cncf.io"
      scope = "Namespaced"
      names = {
        plural   = "network-attachment-definitions"
        singular = "network-attachment-definition"
        kind     = "NetworkAttachmentDefinition"
        shortNames = ["net-attach-def"]
      }
      versions = [{
        name    = "v1"
        served  = true
        storage = true
        schema = {
          openAPIV3Schema = {
            type = "object"
            properties = {
              spec = {
                type = "object"
                properties = {
                  config = {
                    type = "string"
                  }
                }
              }
            }
          }
        }
      }]
    }
  }
}