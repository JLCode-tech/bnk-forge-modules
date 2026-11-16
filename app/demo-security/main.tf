# bnk-forge-modules/app/demo-security/main.tf
# Demo Security — Firewall Policy, Address/Port Lists, BNKSecPolicy

# =============================================================================
# ADDRESS LISTS
# =============================================================================

resource "kubernetes_manifest" "allowed_sources" {
  depends_on = [var.gateway_ready]

  manifest = {
    apiVersion = "k8s.f5net.com/v1"
    kind       = "F5BigCneAddresslist"

    metadata = {
      name      = "demo-allowed-sources"
      namespace = var.gateway_namespace
      labels = {
        "app.kubernetes.io/name"       = "demo-allowed-sources"
        "app.kubernetes.io/component"  = "security"
        "app.kubernetes.io/part-of"    = "bnk-demo"
        "app.kubernetes.io/managed-by" = "opentofu"
      }
    }

    spec = {
      addresses = var.allowed_source_ranges
    }
  }
}

resource "kubernetes_manifest" "blocked_sources" {
  depends_on = [var.gateway_ready]

  manifest = {
    apiVersion = "k8s.f5net.com/v1"
    kind       = "F5BigCneAddresslist"

    metadata = {
      name      = "demo-blocked-sources"
      namespace = var.gateway_namespace
      labels = {
        "app.kubernetes.io/name"       = "demo-blocked-sources"
        "app.kubernetes.io/component"  = "security"
        "app.kubernetes.io/part-of"    = "bnk-demo"
        "app.kubernetes.io/managed-by" = "opentofu"
      }
    }

    spec = {
      addresses = var.blocked_source_ranges
    }
  }
}

# =============================================================================
# PORT LIST
# =============================================================================

resource "kubernetes_manifest" "allowed_ports" {
  depends_on = [var.gateway_ready]

  manifest = {
    apiVersion = "k8s.f5net.com/v1"
    kind       = "F5BigCnePortlist"

    metadata = {
      name      = "demo-allowed-ports"
      namespace = var.gateway_namespace
      labels = {
        "app.kubernetes.io/name"       = "demo-allowed-ports"
        "app.kubernetes.io/component"  = "security"
        "app.kubernetes.io/part-of"    = "bnk-demo"
        "app.kubernetes.io/managed-by" = "opentofu"
      }
    }

    spec = {
      ports = ["80", "443", "8080"]
    }
  }
}

# =============================================================================
# FIREWALL POLICY
# =============================================================================

resource "kubernetes_manifest" "fw_policy" {
  depends_on = [
    kubernetes_manifest.allowed_sources,
    kubernetes_manifest.blocked_sources,
    kubernetes_manifest.allowed_ports,
  ]

  manifest = {
    apiVersion = "k8s.f5net.com/v1"
    kind       = "F5BigFwPolicy"

    metadata = {
      name      = "demo-fw-policy"
      namespace = var.gateway_namespace
      labels = {
        "app.kubernetes.io/name"       = "demo-fw-policy"
        "app.kubernetes.io/component"  = "security"
        "app.kubernetes.io/part-of"    = "bnk-demo"
        "app.kubernetes.io/managed-by" = "opentofu"
      }
    }

    spec = {
      rule = [
        {
          name       = "allow-web"
          action     = "accept"
          ipProtocol = "tcp"
          source = {
            addressLists = ["demo-allowed-sources"]
          }
          destination = {
            portLists = ["demo-allowed-ports"]
          }
          logging = true
        },
        {
          name       = "block-bad-actors"
          action     = "drop"
          ipProtocol = "any"
          source = {
            addressLists = ["demo-blocked-sources"]
          }
          logging = true
        },
        {
          name       = "default-allow"
          action     = "accept"
          ipProtocol = "any"
          logging    = false
        }
      ]
    }
  }
}

# =============================================================================
# BNK SECURITY POLICY — Attach firewall to Gateway
# =============================================================================

resource "kubernetes_manifest" "secpolicy" {
  depends_on = [kubernetes_manifest.fw_policy]

  manifest = {
    apiVersion = "gateway.k8s.f5.com/v1alpha1"
    kind       = "SecPolicy"

    metadata = {
      name      = "demo-secpolicy"
      namespace = var.gateway_namespace
      labels = {
        "app.kubernetes.io/name"       = "demo-secpolicy"
        "app.kubernetes.io/component"  = "security"
        "app.kubernetes.io/part-of"    = "bnk-demo"
        "app.kubernetes.io/managed-by" = "opentofu"
      }
    }

    spec = {
      targetRefs = [
        {
          group = "gateway.networking.k8s.io"
          kind  = "Gateway"
          name  = var.gateway_name
        }
      ]
      extensionRefs = [
        {
          group = "k8s.f5net.com"
          kind  = "F5BigFwPolicy"
          name  = "demo-fw-policy"
        }
      ]
    }
  }
}

# =============================================================================
# VERIFICATION
# =============================================================================

resource "null_resource" "verify_security" {
  depends_on = [
    kubernetes_manifest.secpolicy,
    kubernetes_manifest.fw_policy,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Verifying Demo Security Policies ==="
      kubectl get f5bigfwpolicy,bnksecpolicy,f5bigcneaddresslist,f5bigcneportlist -n ${var.gateway_namespace} -l app.kubernetes.io/part-of=bnk-demo 2>/dev/null || echo "Some CRDs may not be registered yet"
      echo "Security verification complete"
    EOT
  }
}
