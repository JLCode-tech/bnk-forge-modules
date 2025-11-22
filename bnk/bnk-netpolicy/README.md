# BNKNetPolicy Module

## Overview

Creates network policies for BIG-IP Next Gateways including iRules, TCP/HTTP settings, connection pooling, session persistence, SSL profiles, compression, and HSL logging.

## Features

- iRules (inline or referenced)
- TCP profile customization
- HTTP profile configuration
- Connection pooling
- Session persistence (cookie, source-IP, hash)
- Backend SSL/TLS settings
- HTTP compression
- High-speed logging (HSL)

## Dependencies

- **FLO**: For BNKNetPolicy CRD

## Usage

```hcl
module "network_policy" {
  source = "./bnk/bnk-netpolicy"

  cluster_name      = "my-eks-cluster"
  policy_name       = "gateway-network"
  policy_namespace  = "default"

  # iRules
  irules = [
    {
      name = "custom-irule"
    },
    {
      inline = <<-EOT
        when HTTP_REQUEST {
          # Custom iRule logic
          HTTP::header insert X-Custom-Header "value"
        }
      EOT
    }
  ]

  # TCP settings
  tcp_profile = {
    idle_timeout        = "300s"
    keep_alive_interval = "60s"
    nagle_algorithm     = false
  }

  # HTTP settings
  http_profile = {
    xff_enabled     = true
    max_header_size = 32768
    pipeline_mode   = "controlled"
  }

  # Connection pooling
  connection_pool = {
    max_connections      = 1000
    max_idle_connections = 100
    idle_timeout         = "90s"
  }

  # Session persistence
  persistence = {
    type        = "cookie"
    timeout     = "3600s"
    cookie_name = "F5_SESSIONID"
    cookie_method = "insert"
  }

  # Compression
  compression = {
    enabled       = true
    algorithms    = ["gzip", "br"]
    min_size      = 1024
    content_types = ["text/html", "application/json"]
  }

  # HSL logging
  hsl_logging = {
    enabled = true
    publisher_ref = {
      name = "hsl-publisher"
    }
    log_format = "json"
    log_level  = "info"
  }

  flo_ready = module.flo.flo_ready

  common_labels = {
    environment = "production"
  }
}
```

## Attach to Gateway

Policies are attached to Gateways via the Gateway module:

```hcl
module "gateway" {
  source = "./bnk/gateway"

  network_policy_refs = [
    {
      name = module.network_policy.policy_name
    }
  ]
}
```

## Module Metadata

- **Category**: bnk
- **Workflow Compatibility**: Greenfield, Partial
- **Version**: 2.1.x
- **Last Updated**: 2025-11-22
