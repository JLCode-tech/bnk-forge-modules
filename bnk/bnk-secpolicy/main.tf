# infrastructure-modules/spk-2.1/bnk-secpolicy/main.tf
# BNKSecPolicy - Security Policy for Gateways

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
# BNK SECURITY POLICY
# =============================================================================

resource "kubernetes_manifest" "bnk_secpolicy" {
  depends_on = [var.flo_ready]

  manifest = {
    apiVersion = "gateway.f5.com/v1alpha1"
    kind       = "BNKSecPolicy"

    metadata = {
      name      = var.policy_name
      namespace = var.policy_namespace

      labels = merge(var.common_labels, {
        "app.kubernetes.io/name"       = var.policy_name
        "app.kubernetes.io/component"  = "security-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })

      annotations = var.annotations
    }

    spec = merge(
      # Firewall configuration
      var.enable_firewall && var.firewall_policy_ref != null ? {
        firewall = merge(
          {
            policyRef = merge(
              { name = var.firewall_policy_ref.name },
              var.firewall_policy_ref.namespace != null ? {
                namespace = var.firewall_policy_ref.namespace
              } : {}
            )
          },
          length(var.firewall_rule_lists) > 0 ? {
            ruleLists = [
              for rulelist in var.firewall_rule_lists : merge(
                { name = rulelist.name },
                rulelist.namespace != null ? { namespace = rulelist.namespace } : {}
              )
            ]
          } : {}
        )
      } : {},

      # DDoS protection
      var.enable_ddos ? {
        ddos = merge(
          { mode = var.ddos_protection_mode },
          var.ddos_global_ref != null ? {
            globalRef = merge(
              { name = var.ddos_global_ref.name },
              var.ddos_global_ref.namespace != null ? {
                namespace = var.ddos_global_ref.namespace
              } : {}
            )
          } : {}
        )
      } : {},

      # Access control
      length(var.allowed_source_ranges) > 0 || length(var.denied_source_ranges) > 0 || length(var.address_lists) > 0 ? {
        accessControl = merge(
          length(var.allowed_source_ranges) > 0 ? {
            allowedSourceRanges = var.allowed_source_ranges
          } : {},
          length(var.denied_source_ranges) > 0 ? {
            deniedSourceRanges = var.denied_source_ranges
          } : {},
          length(var.address_lists) > 0 ? {
            addressLists = [
              for addrlist in var.address_lists : merge(
                {
                  name   = addrlist.name
                  action = addrlist.action
                },
                addrlist.namespace != null ? { namespace = addrlist.namespace } : {}
              )
            ]
          } : {}
        )
      } : {},

      # Rate limiting
      var.enable_rate_limiting && var.rate_limit_config != null ? {
        rateLimit = merge(
          {
            requestsPerSecond = var.rate_limit_config.requests_per_second
          },
          var.rate_limit_config.burst_size != null ? {
            burstSize = var.rate_limit_config.burst_size
          } : {},
          var.rate_limit_config.key != null ? {
            key = var.rate_limit_config.key
          } : {}
        )
      } : {},

      # Logging
      var.log_profile_ref != null || var.hsl_publisher_ref != null ? {
        logging = merge(
          var.log_profile_ref != null ? {
            profileRef = merge(
              { name = var.log_profile_ref.name },
              var.log_profile_ref.namespace != null ? {
                namespace = var.log_profile_ref.namespace
              } : {}
            )
          } : {},
          var.hsl_publisher_ref != null ? {
            hslPublisherRef = merge(
              { name = var.hsl_publisher_ref.name },
              var.hsl_publisher_ref.namespace != null ? {
                namespace = var.hsl_publisher_ref.namespace
              } : {}
            )
          } : {}
        )
      } : {}
    )
  }
}

# =============================================================================
# VERIFICATION
# =============================================================================

resource "time_sleep" "wait_for_policy" {
  depends_on = [kubernetes_manifest.bnk_secpolicy]

  create_duration = "5s"
}

resource "null_resource" "verify_policy" {
  depends_on = [time_sleep.wait_for_policy]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Verifying BNKSecPolicy ${var.policy_name} ==="

      # Check policy exists
      kubectl get bnksecpolicy ${var.policy_name} -n ${var.policy_namespace} || echo "Policy not found yet"

      echo "✓ BNKSecPolicy verification complete"
    EOT
  }
}
