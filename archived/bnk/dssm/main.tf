# Helm release for F5 dSSM (distributed Session State Management)
resource "helm_release" "dssm" {
  name       = var.release_name
  namespace  = var.namespace
  chart      = "f5-dssm"
  repository = "oci://${var.image_registry}/charts"
  version    = var.dssm_version

  values = [
    yamlencode({
      # Replica count for Sentinel and DB pods
      replicaCount = var.replica_count

      # Image configuration
      image = {
        repository = "${var.image_registry}/images"
      }

      # Image pull secrets for FAR registry
      imagePullSecrets = [
        {
          name = var.far_secret_name
        }
      ]

      # Global configuration
      global = {
        imagePullSecrets = [
          {
            name = var.far_secret_name
          }
        ]
        certmgr = {
          external = false
        }
      }

      # Service Account configuration
      serviceAccount = {
        create = true
        name   = var.release_name
      }

      # Sentinel pod configuration
      sentinel = {
        affinity_type = var.affinity_type

        # Fluentbit sidecar for logging
        fluentbit_sidecar = {
          enabled = true
          image = {
            repository = "${var.image_registry}/images"
          }
          fluentd = {
            host = var.fluentd_host
            port = var.fluentd_port
          }
        }

        # Pod disruption budget
        pod_disruption_budget = {
          min_available = var.pod_disruption_min
        }

        # Resource requests
        resources = {
          requests = {
            cpu    = var.sentinel_cpu_request
            memory = var.sentinel_memory_request
          }
        }
      }

      # DB pod configuration
      db = {
        affinity_type       = var.affinity_type
        persistent_storage  = "enable"
        persistent_storage_gb = var.persistent_storage_gb
        accessMode          = var.access_mode

        # Fluentbit sidecar for logging
        fluentbit_sidecar = {
          enabled = true
          image = {
            repository = "${var.image_registry}/images"
          }
          fluentd = {
            host = var.fluentd_host
            port = var.fluentd_port
          }
        }

        # Pod disruption budget
        pod_disruption_budget = {
          min_available = var.pod_disruption_min
        }

        # Resource requests
        resources = {
          requests = {
            cpu    = var.db_cpu_request
            memory = var.db_memory_request
          }
        }
      }

      # Cert client sidecar
      cert_client_sidecar = {
        image = {
          repository = "${var.image_registry}/images"
        }
      }

      # dSSM Upgrader
      dssmUpgrader = {
        image = {
          repository = "${var.image_registry}/images"
        }
      }

      # ConfigMap settings
      configmap = {
        tls_enabled = true
      }

      # Storage class for persistent volumes
      storageClassName = var.storage_class
    })
  ]

  wait          = true
  wait_for_jobs = true
  timeout       = 600

  depends_on = [
    var.dependencies
  ]
}