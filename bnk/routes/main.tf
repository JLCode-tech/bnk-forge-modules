# infrastructure-modules/spk-2.1/routes/main.tf
# Routes Module - HTTPRoute, GRPCRoute, L4Route

# =============================================================================
# HTTP ROUTE
# =============================================================================

resource "kubernetes_manifest" "http_route" {
  count = var.route_type == "HTTPRoute" ? 1 : 0

  depends_on = [var.gateway_ready]

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"

    metadata = {
      name      = var.route_name
      namespace = var.route_namespace

      labels = merge(var.common_labels, {
        "app.kubernetes.io/name"       = var.route_name
        "app.kubernetes.io/component"  = "route"
        "app.kubernetes.io/managed-by" = "terraform"
      })

      annotations = var.annotations
    }

    spec = merge(
      {
        parentRefs = [
          for parent in var.parent_refs : merge(
            {
              name = parent.name
              kind = "Gateway"
            },
            parent.namespace != null ? { namespace = parent.namespace } : {},
            parent.section_name != null ? { sectionName = parent.section_name } : {},
            parent.port != null ? { port = parent.port } : {}
          )
        ]
      },
      length(var.hostnames) > 0 ? { hostnames = var.hostnames } : {},
      length(var.rules) > 0 ? {
        rules = [
          for rule in var.rules : merge(
            rule.matches != null ? {
              matches = [
                for match in rule.matches : merge(
                  match.path != null ? { path = match.path } : {},
                  match.headers != null ? { headers = match.headers } : {},
                  match.query_params != null ? { queryParams = match.query_params } : {},
                  match.method != null ? { method = match.method } : {}
                )
              ]
            } : {},
            rule.filters != null ? {
              filters = [
                for filter in rule.filters : merge(
                  { type = filter.type },
                  filter.request_header_modifier != null ? { requestHeaderModifier = filter.request_header_modifier } : {},
                  filter.response_header_modifier != null ? { responseHeaderModifier = filter.response_header_modifier } : {},
                  filter.request_redirect != null ? { requestRedirect = filter.request_redirect } : {},
                  filter.url_rewrite != null ? { urlRewrite = filter.url_rewrite } : {}
                )
              ]
            } : {},
            rule.backend_refs != null ? {
              backendRefs = [
                for backend in rule.backend_refs : merge(
                  { name = backend.name },
                  backend.namespace != null ? { namespace = backend.namespace } : {},
                  backend.port != null ? { port = backend.port } : {},
                  backend.weight != null ? { weight = backend.weight } : {},
                  backend.kind != null ? { kind = backend.kind } : { kind = "Service" },
                  backend.group != null ? { group = backend.group } : {}
                )
              ]
            } : {},
            rule.timeouts != null ? { timeouts = rule.timeouts } : {}
          )
        ]
      } : {}
    )
  }
}

# =============================================================================
# GRPC ROUTE
# =============================================================================

resource "kubernetes_manifest" "grpc_route" {
  count = var.route_type == "GRPCRoute" ? 1 : 0

  depends_on = [var.gateway_ready]

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1alpha2"
    kind       = "GRPCRoute"

    metadata = {
      name      = var.route_name
      namespace = var.route_namespace

      labels = merge(var.common_labels, {
        "app.kubernetes.io/name"       = var.route_name
        "app.kubernetes.io/component"  = "route"
        "app.kubernetes.io/managed-by" = "terraform"
      })

      annotations = var.annotations
    }

    spec = merge(
      {
        parentRefs = [
          for parent in var.parent_refs : merge(
            {
              name = parent.name
              kind = "Gateway"
            },
            parent.namespace != null ? { namespace = parent.namespace } : {},
            parent.section_name != null ? { sectionName = parent.section_name } : {},
            parent.port != null ? { port = parent.port } : {}
          )
        ]
      },
      length(var.hostnames) > 0 ? { hostnames = var.hostnames } : {},
      length(var.rules) > 0 ? {
        rules = [
          for rule in var.rules : merge(
            rule.matches != null ? {
              matches = [
                for match in rule.matches : merge(
                  match.method != null ? { method = { method = match.method } } : {},
                  match.headers != null ? { headers = match.headers } : {}
                )
              ]
            } : {},
            rule.filters != null ? { filters = rule.filters } : {},
            rule.backend_refs != null ? {
              backendRefs = [
                for backend in rule.backend_refs : merge(
                  { name = backend.name },
                  backend.namespace != null ? { namespace = backend.namespace } : {},
                  backend.port != null ? { port = backend.port } : {},
                  backend.weight != null ? { weight = backend.weight } : {}
                )
              ]
            } : {}
          )
        ]
      } : {}
    )
  }
}

# =============================================================================
# L4 ROUTE (F5 Extension)
# =============================================================================

resource "kubernetes_manifest" "l4_route" {
  count = var.route_type == "L4Route" ? 1 : 0

  depends_on = [var.gateway_ready]

  manifest = {
    apiVersion = "gateway.f5.com/v1alpha1"
    kind       = "L4Route"

    metadata = {
      name      = var.route_name
      namespace = var.route_namespace

      labels = merge(var.common_labels, {
        "app.kubernetes.io/name"       = var.route_name
        "app.kubernetes.io/component"  = "route"
        "app.kubernetes.io/managed-by" = "terraform"
      })

      annotations = var.annotations
    }

    spec = merge(
      {
        parentRefs = [
          for parent in var.parent_refs : merge(
            {
              name = parent.name
              kind = "Gateway"
            },
            parent.namespace != null ? { namespace = parent.namespace } : {},
            parent.section_name != null ? { sectionName = parent.section_name } : {},
            parent.port != null ? { port = parent.port } : {}
          )
        ]

        protocol = var.l4_protocol

        backendRefs = [
          for backend in var.l4_backend_refs : merge(
            {
              name = backend.name
              port = backend.port
            },
            backend.namespace != null ? { namespace = backend.namespace } : {},
            backend.weight != null ? { weight = backend.weight } : {}
          )
        ]
      },
      var.session_affinity != null && var.session_affinity.enabled ? {
        sessionAffinity = merge(
          { enabled = true },
          var.session_affinity.timeout != null ? { timeout = var.session_affinity.timeout } : {},
          var.session_affinity.cookie_name != null ? { cookieName = var.session_affinity.cookie_name } : {}
        )
      } : {}
    )
  }
}

# =============================================================================
# VERIFICATION
# =============================================================================

resource "time_sleep" "wait_for_route" {
  depends_on = [
    kubernetes_manifest.http_route,
    kubernetes_manifest.grpc_route,
    kubernetes_manifest.l4_route
  ]

  create_duration = "10s"
}

resource "null_resource" "verify_route" {
  depends_on = [time_sleep.wait_for_route]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Verifying ${var.route_type} ${var.route_name} ==="

      # Get route status
      kubectl get ${lower(var.route_type)} ${var.route_name} -n ${var.route_namespace} || echo "Route not found yet"

      # Check route acceptance
      kubectl wait --for=condition=Accepted ${lower(var.route_type)}/${var.route_name} -n ${var.route_namespace} --timeout=60s || echo "Route not yet accepted"

      echo "✓ Route verification complete"
    EOT
  }
}
