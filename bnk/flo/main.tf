# infrastructure-modules/spk-2.1/flo/main.tf
# F5 Lifecycle Operator (FLO) Helm deployment

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
# LOCAL VALUES
# =============================================================================

# TEEM URLs by environment (for licensing)
locals {
  teem_urls = {
    production = {
      cert_url           = "https://product.apis.f5.com/ee/v1"
      entitlement_url    = "https://product-s.apis.f5.com/ee/v1"
      initial_config_url = "https://product-s.apis.f5.com/ee/v1"
    }
    test = {
      cert_url           = "https://product-tst.apis.f5networks.net/ee/v1"
      entitlement_url    = "https://product-s-tst.apis.f5networks.net/ee/v1"
      initial_config_url = "https://product-s-tst.apis.f5networks.net/ee/v1"
    }
  }

  selected_teem = local.teem_urls[var.license_environment]

  # Licensing configuration based on mode
  license_config = var.license_mode == "connected" ? {
    operationMode        = "connected"
    teemCertUrl          = local.selected_teem.cert_url
    teemEntitlementUrl   = local.selected_teem.entitlement_url
    teemInitialConfigUrl = local.selected_teem.initial_config_url
    jwt                  = var.jwt_token != "" ? var.jwt_token : null
  } : {
    operationMode      = "f5licenseproxy"
    f5LicenseProxyUrl  = var.f5_license_proxy_url
  }
}

# =============================================================================
# NAMESPACE CREATION
# =============================================================================

resource "kubernetes_namespace" "flo" {
  metadata {
    name = var.flo_namespace

    labels = merge(var.common_labels, {
      name    = var.flo_namespace
      purpose = "f5-lifecycle-operator"
    })
  }
}

resource "kubernetes_namespace" "ipam" {
  count = var.enable_ipam_operator ? 1 : 0

  metadata {
    name = var.ipam_namespace

    labels = merge(var.common_labels, {
      name    = var.ipam_namespace
      purpose = "f5-ipam-operator"
    })
  }
}

# =============================================================================
# F5 LIFECYCLE OPERATOR HELM RELEASE
# =============================================================================

resource "helm_release" "flo" {
  depends_on = [
    kubernetes_namespace.flo,
    var.cert_manager_ready,
    var.far_setup_complete
  ]

  name       = "flo"
  repository = var.flo_chart_repository
  chart      = "f5-lifecycle-operator"
  version    = var.flo_version
  namespace  = var.flo_namespace

  timeout = 600
  wait    = true

  values = [
    yamlencode({
      # Image configuration
      image = {
        repository = var.image_registry
        pullPolicy = "IfNotPresent"
      }

      # Image pull secrets
      imagePullSecrets = [
        { name = var.far_secret_name }
      ]

      # Service account
      serviceAccount = {
        create = true
        name   = "flo-controller"
      }

      # Licensing configuration
      license = local.license_config

      # IPAM operator configuration
      ipam = {
        enabled   = var.enable_ipam_operator
        namespace = var.ipam_namespace
      }

      # Resource requests and limits
      resources = {
        requests = {
          cpu    = var.flo_cpu_request
          memory = var.flo_memory_request
        }
        limits = {
          cpu    = var.flo_cpu_limit
          memory = var.flo_memory_limit
        }
      }

      # Node placement
      nodeSelector = var.node_selector
      tolerations  = var.tolerations

      # Security context
      securityContext = {
        runAsNonRoot = true
        runAsUser    = 1000
        fsGroup      = 1000
      }

      # Operator settings
      operator = {
        watchNamespace = "" # Empty means watch all namespaces
        leaderElection = {
          enabled = true
        }
      }

      # CRD management (FLO automatically installs CRDs)
      crds = {
        install = true # FLO installs BnkGatewayClass and other CRDs
      }
    })
  ]
}

# =============================================================================
# WAIT FOR FLO TO BE READY
# =============================================================================

resource "time_sleep" "wait_for_flo" {
  depends_on = [helm_release.flo]

  create_duration = "30s" # Wait for FLO operator to become ready
}

# Verify FLO deployment
resource "null_resource" "verify_flo" {
  depends_on = [time_sleep.wait_for_flo]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Verifying F5 Lifecycle Operator Deployment ==="

      # Check FLO pods
      kubectl get pods -n ${var.flo_namespace} -l app=flo

      # Check IPAM pods (if enabled)
      if [ "${var.enable_ipam_operator}" = "true" ]; then
        kubectl get pods -n ${var.ipam_namespace} -l app=ipam-operator
      fi

      # Verify CRDs installed by FLO
      echo ""
      echo "=== Verifying CRDs installed by FLO ==="
      kubectl get crd | grep -E "gatewayclass|gateway" || echo "Gateway CRDs not yet available"

      echo "✓ FLO deployment verification complete"
    EOT
  }
}
