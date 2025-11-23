# infrastructure-modules/spk-2.1/gateway/main.tf
# Gateway API Gateway resource deployment

# =============================================================================
# GATEWAY RESOURCE
# =============================================================================

resource "kubernetes_manifest" "gateway" {
  depends_on = [var.gatewayclass_ready]

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"

    metadata = {
      name      = var.gateway_name
      namespace = var.gateway_namespace

      labels = merge(var.common_labels, {
        "app.kubernetes.io/name"       = var.gateway_name
        "app.kubernetes.io/component"  = "gateway"
        "app.kubernetes.io/managed-by" = "terraform"
      })

      annotations = merge(var.annotations,
        var.enable_ipam && length(var.ipam_selector) > 0 ? {
          "f5.com/ipam-pool-selector" = jsonencode(var.ipam_selector)
        } : {},
        length(var.service_annotations) > 0 ? {
          "f5.com/service-annotations" = jsonencode(var.service_annotations)
        } : {}
      )
    }

    spec = merge(
      {
        gatewayClassName = var.gatewayclass_name

        # Listeners configuration
        listeners = [
          for listener in var.listeners : merge(
            {
              name     = listener.name
              protocol = listener.protocol
              port     = listener.port
            },
            listener.hostname != null ? { hostname = listener.hostname } : {},
            listener.tls != null ? {
              tls = merge(
                { mode = listener.tls.mode },
                listener.tls.certificate_ref != null ? {
                  certificateRefs = [
                    merge(
                      {
                        name = listener.tls.certificate_ref.name
                        kind = "Secret"
                      },
                      listener.tls.certificate_ref.namespace != null ? {
                        namespace = listener.tls.certificate_ref.namespace
                      } : {}
                    )
                  ]
                } : {}
              )
            } : {},
            listener.allowed_routes != null ? {
              allowedRoutes = merge(
                listener.allowed_routes.namespaces != null ? {
                  namespaces = merge(
                    { from = listener.allowed_routes.namespaces.from },
                    listener.allowed_routes.namespaces.selector != null ? {
                      selector = {
                        matchLabels = listener.allowed_routes.namespaces.selector
                      }
                    } : {}
                  )
                } : {},
                listener.allowed_routes.kinds != null ? {
                  kinds = listener.allowed_routes.kinds
                } : {}
              )
            } : {}
          )
        ]
      },

      # Addresses (optional - IPAM manages if not specified)
      length(var.addresses) > 0 ? {
        addresses = var.addresses
      } : {},

      # Infrastructure annotations (F5-specific overrides)
      var.tmm_replicas != null || var.tmm_resources != null || var.network_attachments != null || var.service_type != null ? {
        infrastructure = {
          annotations = merge(
            var.tmm_replicas != null ? {
              "f5.com/tmm-replicas" = tostring(var.tmm_replicas)
            } : {},
            var.tmm_resources != null ? {
              "f5.com/tmm-resources" = jsonencode({
                requests = {
                  cpu             = var.tmm_resources.cpu
                  memory          = var.tmm_resources.memory
                  "hugepages-2Mi" = var.tmm_resources.hugepages_2mi
                }
              })
            } : {},
            var.network_attachments != null ? {
              "f5.com/network-attachments" = jsonencode(var.network_attachments)
            } : {},
            var.service_type != null ? {
              "f5.com/service-type" = var.service_type
            } : {}
          )
        }
      } : {}
    )
  }
}

# =============================================================================
# POLICY ATTACHMENTS (if specified)
# =============================================================================

# BNKSecPolicy attachments
resource "kubernetes_manifest" "security_policy_attachment" {
  for_each = { for idx, policy in var.security_policy_refs : idx => policy }

  depends_on = [kubernetes_manifest.gateway]

  manifest = {
    apiVersion = "gateway.f5.com/v1alpha1"
    kind       = "PolicyAttachment"

    metadata = {
      name      = "${var.gateway_name}-secpolicy-${each.key}"
      namespace = var.gateway_namespace

      labels = merge(var.common_labels, {
        "app.kubernetes.io/name"      = "${var.gateway_name}-secpolicy"
        "app.kubernetes.io/component" = "policy"
      })
    }

    spec = {
      targetRef = {
        group = "gateway.networking.k8s.io"
        kind  = "Gateway"
        name  = var.gateway_name
      }

      policyRef = {
        group     = "gateway.f5.com"
        kind      = "BNKSecPolicy"
        name      = each.value.name
        namespace = each.value.namespace != null ? each.value.namespace : var.gateway_namespace
      }
    }
  }
}

# BNKNetPolicy attachments
resource "kubernetes_manifest" "network_policy_attachment" {
  for_each = { for idx, policy in var.network_policy_refs : idx => policy }

  depends_on = [kubernetes_manifest.gateway]

  manifest = {
    apiVersion = "gateway.f5.com/v1alpha1"
    kind       = "PolicyAttachment"

    metadata = {
      name      = "${var.gateway_name}-netpolicy-${each.key}"
      namespace = var.gateway_namespace

      labels = merge(var.common_labels, {
        "app.kubernetes.io/name"      = "${var.gateway_name}-netpolicy"
        "app.kubernetes.io/component" = "policy"
      })
    }

    spec = {
      targetRef = {
        group = "gateway.networking.k8s.io"
        kind  = "Gateway"
        name  = var.gateway_name
      }

      policyRef = {
        group     = "gateway.f5.com"
        kind      = "BNKNetPolicy"
        name      = each.value.name
        namespace = each.value.namespace != null ? each.value.namespace : var.gateway_namespace
      }
    }
  }
}

# =============================================================================
# WAIT FOR GATEWAY TO BE READY
# =============================================================================

resource "time_sleep" "wait_for_gateway" {
  depends_on = [kubernetes_manifest.gateway]

  create_duration = "30s"
}

resource "null_resource" "verify_gateway" {
  depends_on = [time_sleep.wait_for_gateway]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Verifying Gateway ${var.gateway_name} ==="

      # Check Gateway status
      kubectl get gateway ${var.gateway_name} -n ${var.gateway_namespace}

      # Wait for Gateway to be programmed
      kubectl wait --for=condition=Programmed gateway/${var.gateway_name} -n ${var.gateway_namespace} --timeout=120s || echo "Gateway not yet programmed"

      # Show Gateway addresses
      kubectl get gateway ${var.gateway_name} -n ${var.gateway_namespace} -o jsonpath='{.status.addresses}' | jq . || echo "No addresses assigned yet"

      echo "✓ Gateway verification complete"
    EOT
  }
}
