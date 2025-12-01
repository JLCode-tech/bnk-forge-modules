# Extract cert-gen utility from FAR setup
resource "null_resource" "extract_cert_gen" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Extracting F5 cert-gen utility ==="
      
      # Check if cert-gen already extracted
      if [ ! -d "cert-gen" ]; then
        # Find the cert-gen tarball
        CERT_GEN_TAR=$(find . -name "f5-cert-gen*.tgz" 2>/dev/null | head -1)
        
        if [ -z "$CERT_GEN_TAR" ]; then
          echo "ERROR: f5-cert-gen tarball not found"
          echo "Please download f5-cert-gen from FAR or place in module directory"
          exit 1
        fi
        
        echo "Found cert-gen: $CERT_GEN_TAR"
        tar xvf "$CERT_GEN_TAR"
        echo "✓ cert-gen utility extracted"
      else
        echo "✓ cert-gen utility already available"
      fi
    EOT
  }
}

# Generate CWC API certificates
resource "null_resource" "generate_cwc_certs" {
  depends_on = [null_resource.extract_cert_gen]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Generating CWC API Certificates ==="
      
      # Generate certificates for CWC REST API
      sh cert-gen/gen_cert.sh -s=api-server -a=f5-spk-cwc.${var.namespace} -n=1
      
      echo "✓ CWC license certificates generated: cwc-license-certs.yaml"
    EOT
  }
  
  triggers = {
    namespace = var.namespace
  }
}

# Generate Qkview certificates
resource "null_resource" "generate_qkview_certs" {
  depends_on = [null_resource.extract_cert_gen]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Generating Qkview Certificates ==="
      
      # Generate certificates for Qkview API
      sh cert-gen/gen_cert.sh -s=qkview -a=f5-spk-cwc.${var.namespace} -n=1
      
      echo "✓ Qkview certificates generated"
    EOT
  }
  
  triggers = {
    namespace = var.namespace
  }
}

# Apply certificate secrets to cluster
resource "null_resource" "apply_certificates" {
  depends_on = [
    null_resource.generate_cwc_certs,
    null_resource.generate_qkview_certs
  ]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Applying Certificate Secrets ==="
      
      kubectl apply -f cwc-license-certs.yaml -n ${var.namespace}
      kubectl apply -f qkview-server-certs.yaml -n ${var.namespace}
      kubectl apply -f qkview-client-certs.yaml -n ${var.namespace}
      
      echo "✓ All certificate secrets applied to ${var.namespace}"
    EOT
  }
  
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      kubectl delete secret cwc-license-certs -n ${self.triggers.namespace} --ignore-not-found=true
      kubectl delete secret qkview-server-certs -n ${self.triggers.namespace} --ignore-not-found=true
      kubectl delete secret qkview-client-certs -n ${self.triggers.namespace} --ignore-not-found=true
    EOT
  }
  
  triggers = {
    namespace = var.namespace
  }
}

# Fetch JWKS from F5 API
data "http" "jwks" {
  url = "https://product.apis.f5.com/ee/v1/keys/jwks"
  
  request_headers = {
    Content-Type = "application/json"
  }
}

# Create JWKS ConfigMap
resource "kubernetes_config_map" "jwks" {
  depends_on = [null_resource.apply_certificates]
  
  metadata {
    name      = "cpcl-key-cm"
    namespace = var.namespace
  }

  data = {
    "jwt.key" = data.http.jwks.response_body
  }
}

# TEEM URLs by environment
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
}

# RabbitMQ Helm Release
resource "helm_release" "rabbitmq" {
  depends_on = [null_resource.apply_certificates]
  
  name       = "spk-rabbit"
  namespace  = var.namespace
  chart      = "rabbitmq"
  repository = "oci://repo.f5.com/charts"
  version    = var.rabbitmq_version

  values = [
    yamlencode({
      # Image at root level (required by chart)
      image = {
        repository = var.image_registry
        name       = "rabbit"
      }
      
      # Fluentbit sidecar
      fluentbit_sidecar = {
        image = {
          repository = var.image_registry
          name       = "f5-fluentbit"
        }
      }
      
      # Version validator
      versionValidator = {
        image = {
          repository = var.image_registry
          name       = "version-validator"
        }
      }
      
      # Service Account
      serviceAccount = {
        create = true
        name   = "f5-rabbitmq"
      }
      
      # Image pull secrets
      imageCredentials = {
        name = var.far_secret_name
      }
      
      global = {
        imagePullSecrets = [
          { name = var.far_secret_name }
        ]
      }
      
      # Persistence
      persistence = {
        enabled      = true
        size         = "8Gi"
        storageClass = var.storage_class
      }
      
      # Resources
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
      
      # Node selector
      nodeSelector = var.node_selector
    })
  ]

  wait    = true
  timeout = 600
}

# CWC Helm Release
resource "helm_release" "cwc" {
  depends_on = [
    helm_release.rabbitmq,
    kubernetes_config_map.jwks,
    null_resource.apply_certificates
  ]
  
  name       = "spk-cwc"
  namespace  = var.namespace
  chart      = "cwc"
  repository = "oci://repo.f5.com/charts"
  version    = var.cwc_version

  values = [
    yamlencode({
      cwc = {
        image = {
          repository = var.image_registry
          name       = "spk-cwc"
        }
      }
      
      orch = {
        image = {
          repository = var.image_registry
          name       = "f5-csm-qkview"
        }
      }
      
      fluentbit_sidecar = {
        image = {
          repository = var.image_registry
          name       = "f5-fluentbit"
        }
      }
      
      versionValidator = {
        image = {
          repository = var.image_registry
          name       = "version-validator"
        }
      }
      
      serviceAccount = {
        create = true
        name   = "f5-spk-cwc"
      }
      
      rabbitmqNamespace = var.namespace
      
      cpclConfig = var.connected_mode ? merge(
        {
          operationMode        = "connected"
          teemCertUrl          = local.selected_teem.cert_url
          teemEntitlementUrl   = local.selected_teem.entitlement_url
          teemInitialConfigUrl = local.selected_teem.initial_config_url
        },
        var.jwt_token != "" ? { jwt = var.jwt_token } : {}
      ) : merge(
        {
          operationMode = "disconnected"
        },
        var.jwt_token != "" ? { jwt = var.jwt_token } : {}
      )
      
      persistence = {
        enabled      = true
        size         = "2Gi"
        storageClass = var.storage_class
      }
      
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
      
      nodeSelector = var.node_selector
      
      imageCredentials = {
        name = var.far_secret_name
      }
      
      global = {
        imagePullSecrets = [
          { name = var.far_secret_name }
        ]
      }
    })
  ]

  wait    = true
  timeout = 600
}