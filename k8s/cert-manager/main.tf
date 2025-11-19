# Helm release for F5 cert-manager
resource "helm_release" "cert_manager" {
  name       = var.release_name
  namespace  = var.namespace
  chart      = "f5-cert-manager"
  repository = "oci://repo.f5.com/charts"
  version    = var.cert_manager_version

  # Values for cert-manager configuration
  values = [
    yamlencode({
      # Image repository for all components
      image = {
        repository = "repo.f5.com/images"
      }
      
      # Webhook component
      webhook = {
        image = {
          repository = "repo.f5.com/images"
        }
      }
      
      # CA Injector component
      cainjector = {
        image = {
          repository = "repo.f5.com/images"
        }
      }
      
      # Startup API check component
      startupapicheck = {
        image = {
          repository = "repo.f5.com/images"
        }
      }
      
      # Init container
      init_container = {
        image = {
          repository = "repo.f5.com/images"
        }
      }
      
      # ServiceAccount configuration - use default, don't create new
      serviceAccount = {
        create = false
        name   = "default"
      }
      
      # Image pull secrets for FAR registry
      global = {
        imagePullSecrets = [
          {
            name = var.far_secret_name
          }
        ]
      }
    })
  ]

  # Wait for resources to be ready
  wait          = true
  wait_for_jobs = true
  timeout       = 600
}