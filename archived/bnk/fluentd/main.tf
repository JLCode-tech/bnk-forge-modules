# infrastructure-modules/spk-2.1/fluentd/main.tf

# -----------------------------------------------------------------------------
# HELM RELEASE - F5 FLUENTD
# -----------------------------------------------------------------------------

resource "helm_release" "fluentd" {
  name       = var.release_name
  namespace  = var.namespace
  chart      = "f5-toda-fluentd"
  repository = "oci://repo.f5.com/charts"
  version    = var.fluentd_version

  # Values configuration for Fluentd
  values = [
    yamlencode({
      # Image configuration
      image = {
        repository = "${var.image_registry}/images"
      }

      # Image pull authentication - dual pattern for FAR registry
      imageCredentials = {
        name = var.far_secret_name
      }

      global = {
        imagePullSecrets = [
          {
            name = var.far_secret_name
          }
        ]
      }

      # Service account configuration - use default account
      serviceAccount = {
        create = false
        name   = "default"
      }

      # Persistence configuration - required for log storage
      persistence = {
        enabled      = true
        storageClass = var.storage_class
        size         = var.storage_size
      }

      # Resource limits and requests
      resources = var.resources

      # Node selector for pod placement
      nodeSelector = var.node_selector

      # Logging configurations - enable log collection from all SPK components
      # Required for proper log file recovery on pod/container restarts
      
      # F5 Ingress Controller logging
      f5ingress_logs = {
        enabled = true
        stdout  = true
      }

      # dSSM Database logging
      dssm_logs = {
        enabled = true
        stdout  = true
      }

      # dSSM Sentinel logging
      dssm_sentinel_logs = {
        enabled = true
        stdout  = true
      }

      # Cert Manager logging
      cm_logs = {
        enabled = true
        stdout  = true
      }

      # Kafka plugin configuration (disabled by default)
      kafkaPlugin = {
        enabled = false
      }
    })
  ]

  # Deployment settings
  wait          = true
  wait_for_jobs = true
  timeout       = 600

  # Dependencies - ensure prerequisites are met
  depends_on = [
    var.far_setup_complete,
    var.cert_manager_complete,
    var.storage_classes_deployed
  ]
}