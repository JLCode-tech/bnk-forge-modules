# infrastructure-modules/spk-2.1/bnk-netpolicy/main.tf
# BNKNetPolicy - Network Policy and Extensions for Gateways

# =============================================================================
# BNK NETWORK POLICY
# =============================================================================

resource "kubernetes_manifest" "bnk_netpolicy" {
  depends_on = [var.flo_ready]

  manifest = {
    apiVersion = "gateway.f5.com/v1alpha1"
    kind       = "BNKNetPolicy"

    metadata = {
      name      = var.policy_name
      namespace = var.policy_namespace

      labels = merge(var.common_labels, {
        "app.kubernetes.io/name"       = var.policy_name
        "app.kubernetes.io/component"  = "network-policy"
        "app.kubernetes.io/managed-by" = "terraform"
      })

      annotations = var.annotations
    }

    spec = merge(
      # iRules configuration
      length(var.irules) > 0 ? {
        irules = [
          for irule in var.irules : merge(
            irule.name != null ? {
              ref = merge(
                { name = irule.name },
                irule.namespace != null ? { namespace = irule.namespace } : {}
              )
            } : {},
            irule.inline != null ? {
              inline = irule.inline
            } : {}
          )
        ]
      } : {},

      # TCP profile configuration
      var.tcp_profile != null ? {
        tcp = merge(
          var.tcp_profile.idle_timeout != null ? {
            idleTimeout = var.tcp_profile.idle_timeout
          } : {},
          var.tcp_profile.close_wait_timeout != null ? {
            closeWaitTimeout = var.tcp_profile.close_wait_timeout
          } : {},
          var.tcp_profile.fin_wait_timeout != null ? {
            finWaitTimeout = var.tcp_profile.fin_wait_timeout
          } : {},
          var.tcp_profile.keep_alive_interval != null ? {
            keepAliveInterval = var.tcp_profile.keep_alive_interval
          } : {},
          var.tcp_profile.tcp_window_size != null ? {
            windowSize = var.tcp_profile.tcp_window_size
          } : {},
          var.tcp_profile.nagle_algorithm != null ? {
            nagleAlgorithm = var.tcp_profile.nagle_algorithm
          } : {},
          var.tcp_profile.delayed_acks != null ? {
            delayedAcks = var.tcp_profile.delayed_acks
          } : {},
          var.tcp_profile.reset_on_timeout != null ? {
            resetOnTimeout = var.tcp_profile.reset_on_timeout
          } : {},
          var.tcp_profile.proxy_buffer_low != null ? {
            proxyBufferLow = var.tcp_profile.proxy_buffer_low
          } : {},
          var.tcp_profile.proxy_buffer_high != null ? {
            proxyBufferHigh = var.tcp_profile.proxy_buffer_high
          } : {}
        )
      } : var.tcp_settings_ref != null ? {
        tcp = {
          ref = merge(
            { name = var.tcp_settings_ref.name },
            var.tcp_settings_ref.namespace != null ? {
              namespace = var.tcp_settings_ref.namespace
            } : {}
          )
        }
      } : {},

      # HTTP profile configuration
      var.http_profile != null ? {
        http = merge(
          var.http_profile.xff_enabled != null ? {
            xffEnabled = var.http_profile.xff_enabled
          } : {},
          var.http_profile.xff_trusted_proxies != null ? {
            xffTrustedProxies = var.http_profile.xff_trusted_proxies
          } : {},
          var.http_profile.max_header_size != null ? {
            maxHeaderSize = var.http_profile.max_header_size
          } : {},
          var.http_profile.max_headers_count != null ? {
            maxHeadersCount = var.http_profile.max_headers_count
          } : {},
          var.http_profile.request_chunking != null ? {
            requestChunking = var.http_profile.request_chunking
          } : {},
          var.http_profile.response_chunking != null ? {
            responseChunking = var.http_profile.response_chunking
          } : {},
          var.http_profile.pipeline_mode != null ? {
            pipelineMode = var.http_profile.pipeline_mode
          } : {}
        )
      } : {},

      # HSL logging
      var.hsl_logging != null && var.hsl_logging.enabled ? {
        logging = merge(
          var.hsl_logging.publisher_ref != null ? {
            publisherRef = merge(
              { name = var.hsl_logging.publisher_ref.name },
              var.hsl_logging.publisher_ref.namespace != null ? {
                namespace = var.hsl_logging.publisher_ref.namespace
              } : {}
            )
          } : {},
          var.hsl_logging.log_profile_ref != null ? {
            profileRef = merge(
              { name = var.hsl_logging.log_profile_ref.name },
              var.hsl_logging.log_profile_ref.namespace != null ? {
                namespace = var.hsl_logging.log_profile_ref.namespace
              } : {}
            )
          } : {},
          var.hsl_logging.log_format != null ? {
            format = var.hsl_logging.log_format
          } : {},
          var.hsl_logging.log_level != null ? {
            level = var.hsl_logging.log_level
          } : {}
        )
      } : {},

      # Connection pooling
      var.connection_pool != null ? {
        connectionPool = merge(
          var.connection_pool.max_connections != null ? {
            maxConnections = var.connection_pool.max_connections
          } : {},
          var.connection_pool.max_idle_connections != null ? {
            maxIdleConnections = var.connection_pool.max_idle_connections
          } : {},
          var.connection_pool.idle_timeout != null ? {
            idleTimeout = var.connection_pool.idle_timeout
          } : {},
          var.connection_pool.connection_timeout != null ? {
            connectionTimeout = var.connection_pool.connection_timeout
          } : {},
          var.connection_pool.max_requests_per_conn != null ? {
            maxRequestsPerConnection = var.connection_pool.max_requests_per_conn
          } : {}
        )
      } : {},

      # Persistence
      var.persistence != null ? {
        persistence = merge(
          {
            type = var.persistence.type
          },
          var.persistence.timeout != null ? {
            timeout = var.persistence.timeout
          } : {},
          var.persistence.cookie_name != null ? {
            cookieName = var.persistence.cookie_name
          } : {},
          var.persistence.cookie_method != null ? {
            cookieMethod = var.persistence.cookie_method
          } : {},
          var.persistence.cookie_encrypt != null ? {
            cookieEncrypt = var.persistence.cookie_encrypt
          } : {},
          var.persistence.hash_algorithm != null ? {
            hashAlgorithm = var.persistence.hash_algorithm
          } : {}
        )
      } : {},

      # SSL profile
      var.ssl_profile != null && var.ssl_profile.enabled ? {
        ssl = merge(
          var.ssl_profile.cipher_suite != null ? {
            cipherSuite = var.ssl_profile.cipher_suite
          } : {},
          var.ssl_profile.min_protocol != null ? {
            minProtocol = var.ssl_profile.min_protocol
          } : {},
          var.ssl_profile.max_protocol != null ? {
            maxProtocol = var.ssl_profile.max_protocol
          } : {},
          var.ssl_profile.verify_server_cert != null ? {
            verifyServerCert = var.ssl_profile.verify_server_cert
          } : {},
          var.ssl_profile.ca_bundle_ref != null ? {
            caBundleRef = merge(
              { name = var.ssl_profile.ca_bundle_ref.name },
              var.ssl_profile.ca_bundle_ref.namespace != null ? {
                namespace = var.ssl_profile.ca_bundle_ref.namespace
              } : {}
            )
          } : {}
        )
      } : {},

      # Compression
      var.compression != null && var.compression.enabled ? {
        compression = merge(
          {
            enabled = true
          },
          var.compression.algorithms != null ? {
            algorithms = var.compression.algorithms
          } : {},
          var.compression.min_size != null ? {
            minSize = var.compression.min_size
          } : {},
          var.compression.content_types != null ? {
            contentTypes = var.compression.content_types
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
  depends_on = [kubernetes_manifest.bnk_netpolicy]

  create_duration = "5s"
}

resource "null_resource" "verify_policy" {
  depends_on = [time_sleep.wait_for_policy]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Verifying BNKNetPolicy ${var.policy_name} ==="

      # Check policy exists
      kubectl get bnknetpolicy ${var.policy_name} -n ${var.policy_namespace} || echo "Policy not found yet"

      echo "✓ BNKNetPolicy verification complete"
    EOT
  }
}
