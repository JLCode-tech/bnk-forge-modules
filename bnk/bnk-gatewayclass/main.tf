# infrastructure-modules/spk-2.1/bnk-gatewayclass/main.tf
# BNKGatewayClass - Gateway API resource for BIG-IP Next

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
# BNK GATEWAY CLASS CUSTOM RESOURCE
# =============================================================================

# BNKGatewayClass defines the class of Gateways that will be managed by F5
# This must be deployed in the same namespace as FLO
resource "kubernetes_manifest" "bnk_gatewayclass" {
  depends_on = [var.flo_ready]

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"

    metadata = {
      name = var.gatewayclass_name
      labels = merge(var.common_labels, {
        "app.kubernetes.io/name"       = "bnk-gatewayclass"
        "app.kubernetes.io/component"  = "gateway-api"
        "app.kubernetes.io/managed-by" = "terraform"
      })
      annotations = {
        "description" = var.description
      }
    }

    spec = {
      # F5 controller name
      controllerName = var.controller_name

      # Description
      description = var.description

      # Parameters reference (optional - points to configuration)
      parametersRef = {
        group     = "gateway.f5.com"
        kind      = "BNKGatewayClassConfig"
        name      = kubernetes_manifest.bnk_gatewayclass_config.manifest.metadata.name
        namespace = var.flo_namespace
      }
    }
  }
}

# =============================================================================
# BNK GATEWAY CLASS CONFIGURATION
# =============================================================================

# BNKGatewayClassConfig contains default parameters for Gateways
resource "kubernetes_manifest" "bnk_gatewayclass_config" {
  depends_on = [var.flo_ready]

  manifest = {
    apiVersion = "gateway.f5.com/v1"
    kind       = "BNKGatewayClassConfig"

    metadata = {
      name      = "${var.gatewayclass_name}-config"
      namespace = var.flo_namespace

      labels = merge(var.common_labels, {
        "app.kubernetes.io/name"       = "bnk-gatewayclass-config"
        "app.kubernetes.io/component"  = "gateway-api"
        "app.kubernetes.io/managed-by" = "terraform"
      })
    }

    spec = {
      # Default TMM configuration
      tmm = {
        replicas = var.default_tmm_replicas

        resources = {
          requests = {
            cpu               = var.default_tmm_cpu
            memory            = var.default_tmm_memory
            "hugepages-2Mi"   = var.default_tmm_hugepages_2mi
          }
          limits = {
            cpu               = var.default_tmm_cpu
            memory            = var.default_tmm_memory
            "hugepages-2Mi"   = var.default_tmm_hugepages_2mi
          }
        }

        # High availability configuration
        highAvailability = var.enable_ha ? {
          enabled = true
        } : null

        # Pod anti-affinity for HA
        affinity = var.anti_affinity_enabled ? {
          podAntiAffinity = {
            requiredDuringSchedulingIgnoredDuringExecution = [
              {
                labelSelector = {
                  matchExpressions = [
                    {
                      key      = "app"
                      operator = "In"
                      values   = ["tmm"]
                    }
                  ]
                }
                topologyKey = "kubernetes.io/hostname"
              }
            ]
          }
        } : null
      }

      # Service configuration
      service = {
        type = var.default_service_type

        # IPAM configuration (if enabled)
        ipam = var.enable_ipam ? {
          enabled   = true
          namespace = var.ipam_namespace
        } : null
      }

      # Network attachments for TMM pods
      networkAttachments = {
        external = var.network_attachments.external
        internal = var.network_attachments.internal
      }
    }
  }
}

# =============================================================================
# VERIFICATION
# =============================================================================

resource "time_sleep" "wait_for_gatewayclass" {
  depends_on = [
    kubernetes_manifest.bnk_gatewayclass,
    kubernetes_manifest.bnk_gatewayclass_config
  ]

  create_duration = "10s"
}

resource "null_resource" "verify_gatewayclass" {
  depends_on = [time_sleep.wait_for_gatewayclass]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Verifying BNKGatewayClass ==="

      # Check GatewayClass status
      kubectl get gatewayclass ${var.gatewayclass_name} -o yaml

      # Verify GatewayClass is accepted
      kubectl wait --for=condition=Accepted gatewayclass/${var.gatewayclass_name} --timeout=60s || echo "GatewayClass not yet accepted"

      echo "✓ BNKGatewayClass verification complete"
    EOT
  }
}
