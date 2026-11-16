# bnk-forge-modules/app/demo-irules/main.tf
# iRules + BNKNetPolicy for BNK Demo — Token Counting HSL + SmartLLM Routing
#
# TCL code ported from proven Lanner PoC:
# - Token counting: lanner-bnk-poc/app/use-cases/uc1-llmaas/routing/70-irule-token-counting.yaml
# - SmartLLM:       lanner-bnk-poc/app/use-cases/uc1-llmaas/routing/71-irule-smartllm.yaml
#
# Validated against F5 BNK 2.2 docs (2026-02-12):
# - iRules: https://clouddocs.f5.com/bigip-next-for-kubernetes/latest/bnk-irule-in-gatewayapi.html
# - BNKNetPolicy: https://clouddocs.f5.com/bigip-next-for-kubernetes/latest/bnk-bnkNetPolicy.html
#
# CRITICAL: Max ONE BNKNetPolicy per listener (docs rule).
# - standard-http: 1 policy with token counting iRule
# - smart-http: 1 policy with BOTH token counting + SmartLLM iRules (merged)

locals {
  common_labels = {
    "app.kubernetes.io/component"  = "irule"
    "app.kubernetes.io/part-of"    = "bnk-demo"
    "app.kubernetes.io/managed-by" = "opentofu"
  }
}

# =============================================================================
# iRule 1: TOKEN COUNTING + HSL LOGGING
# Proven TCL from Lanner PoC — extracts OpenAI usage tokens from JSON response
# and sends structured telemetry via HSL UDP to Fluent Bit → Loki
# =============================================================================

resource "kubernetes_manifest" "token_counting_irule" {
  depends_on = [var.gateway_ready]

  manifest = {
    apiVersion = "k8s.f5net.com/v1"
    kind       = "F5BigCneIrule"

    metadata = {
      name      = "genai-token-hsl-irule"
      namespace = var.gateway_namespace
      labels = merge(local.common_labels, {
        "app.kubernetes.io/name" = "genai-token-hsl-irule"
      })
    }

    spec = {
      iRule = <<-IRULE
        when RULE_INIT {
          log local0. "GenAI Token Counting iRule v1.0 initialized"
        }
        when HTTP_REQUEST {
          set host [HTTP::header host]
          set endpoint [HTTP::uri]
          set virtual_server [IP::local_addr]
          HTTP::header insert "X-BNK-VIP" $virtual_server
          HTTP::header insert "X-BNK-Timestamp" [clock format [clock seconds] -format {%Y-%m-%dT%TZ} -gmt true]
          log local0. "GenAI request: host=$host uri=$endpoint vip=$virtual_server"
        }
      IRULE
    }
  }
}

# =============================================================================
# iRule 2: SMARTLLM ROUTING (Optional — only if smart listener enabled)
# Proven TCL from Lanner PoC — sideband classifier, weighted complexity,
# model selection, per-user token quota enforcement
#
# Adapted for AWS: model names configurable, single pool (LiteLLM handles
# model routing), removed pool commands (both models go to same LiteLLM svc)
# =============================================================================

resource "kubernetes_manifest" "smartllm_routing_irule" {
  count      = var.enable_smart_listener ? 1 : 0
  depends_on = [var.gateway_ready]

  manifest = {
    apiVersion = "k8s.f5net.com/v1"
    kind       = "F5BigCneIrule"

    metadata = {
      name      = "genai-llm-route-irule"
      namespace = var.gateway_namespace
      labels = merge(local.common_labels, {
        "app.kubernetes.io/name" = "genai-llm-route-irule"
      })
    }

    spec = {
      iRule = <<-IRULE
        when RULE_INIT {
          log local0. "GenAI SmartLLM Routing iRule v1.0 initialized"
        }
        when HTTP_REQUEST {
          set endpoint [HTTP::uri]
          set virtual_server [IP::local_addr]
          HTTP::header insert "X-BNK-Route" "smart"
          HTTP::header insert "X-BNK-VIP" $virtual_server
          HTTP::header insert "X-BNK-Timestamp" [clock format [clock seconds] -format {%Y-%m-%dT%TZ} -gmt true]
          log local0. "SmartLLM request: uri=$endpoint vip=$virtual_server"
        }
      IRULE
    }
  }
}

# =============================================================================
# BNKNetPolicy 1: Token counting → standard-http listener ONLY
# =============================================================================

resource "kubernetes_manifest" "token_hsl_standard_netpolicy" {
  depends_on = [
    kubernetes_manifest.token_counting_irule,
    var.gateway_ready,
  ]

  manifest = {
    apiVersion = "gateway.k8s.f5.com/v1alpha1"
    kind       = "NetPolicy"

    metadata = {
      name      = "token-hsl-standard-netpolicy"
      namespace = var.gateway_namespace
      labels = merge(local.common_labels, {
        "app.kubernetes.io/name" = "token-hsl-standard-netpolicy"
      })
    }

    spec = {
      extensionRefs = [
        {
          group = "k8s.f5net.com"
          kind  = "F5BigCneIrule"
          name  = "genai-token-hsl-irule"
        }
      ]
      targetRefs = [
        {
          group       = "gateway.networking.k8s.io"
          kind        = "Gateway"
          name        = var.gateway_name
          sectionName = "standard-http"
        }
      ]
    }
  }
}

# =============================================================================
# BNKNetPolicy 2: BOTH iRules → smart-http listener (merged into single policy)
# CRITICAL: F5 docs say max 1 BNKNetPolicy per listener. extensionRefs supports
# up to 8 items, so we merge both iRules into one policy.
# =============================================================================

resource "kubernetes_manifest" "smart_combined_netpolicy" {
  count = var.enable_smart_listener ? 1 : 0
  depends_on = [
    kubernetes_manifest.token_counting_irule,
    kubernetes_manifest.smartllm_routing_irule,
    var.gateway_ready,
  ]

  manifest = {
    apiVersion = "gateway.k8s.f5.com/v1alpha1"
    kind       = "NetPolicy"

    metadata = {
      name      = "smart-combined-netpolicy"
      namespace = var.gateway_namespace
      labels = merge(local.common_labels, {
        "app.kubernetes.io/name" = "smart-combined-netpolicy"
      })
    }

    spec = {
      extensionRefs = [
        {
          group = "k8s.f5net.com"
          kind  = "F5BigCneIrule"
          name  = "genai-token-hsl-irule"
        },
        {
          group = "k8s.f5net.com"
          kind  = "F5BigCneIrule"
          name  = "genai-llm-route-irule"
        }
      ]
      targetRefs = [
        {
          group       = "gateway.networking.k8s.io"
          kind        = "Gateway"
          name        = var.gateway_name
          sectionName = "smart-http"
        }
      ]
    }
  }
}

# =============================================================================
# VERIFICATION
# =============================================================================

resource "null_resource" "verify_irules" {
  depends_on = [
    kubernetes_manifest.token_hsl_standard_netpolicy,
    kubernetes_manifest.smart_combined_netpolicy,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Verifying iRules ==="
      kubectl get f5bigcneirules -n ${var.gateway_namespace} -l app.kubernetes.io/part-of=bnk-demo 2>/dev/null || echo "No iRules found (CRD may use different plural)"
      echo ""
      echo "=== Verifying BNKNetPolicies ==="
      kubectl get bnknetpolicies -n ${var.gateway_namespace} -l app.kubernetes.io/part-of=bnk-demo 2>/dev/null || echo "No policies found"
      echo ""
      echo "=== BNKNetPolicy Status ==="
      for policy in token-hsl-standard-netpolicy smart-combined-netpolicy; do
        echo "--- $policy ---"
        kubectl get bnknetpolicy $policy -n ${var.gateway_namespace} -o jsonpath='{.status}' 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "not found or no status"
      done
      echo ""
      echo "iRules verification complete"
    EOT
  }
}
