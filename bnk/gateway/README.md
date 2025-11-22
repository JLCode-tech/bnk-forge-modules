# Gateway Module

## Overview

Creates a Gateway API Gateway instance that serves as the entry point for external traffic. Gateways configure listeners, addresses, and TLS termination for routing traffic to backend services.

## Features

- Standard Kubernetes Gateway API compliance
- Multiple listener support (HTTP, HTTPS, TCP, UDP, TLS)
- TLS termination and passthrough
- IPAM integration for automatic IP allocation
- Policy attachments (security and network policies)
- TMM resource and replica overrides
- Service type configuration

## Dependencies

- **BNKGatewayClass**: Gateway class must exist
- **FLO**: For Gateway API CRDs

## Usage

```hcl
module "gateway" {
  source = "./bnk/gateway"

  # Cluster configuration
  cluster_name = "my-eks-cluster"

  # Gateway configuration
  gateway_name      = "my-gateway"
  gateway_namespace = "default"
  gatewayclass_name = "bnk-gatewayclass"

  # Listeners
  listeners = [
    {
      name     = "http"
      protocol = "HTTP"
      port     = 80
      allowed_routes = {
        namespaces = {
          from = "Same"
        }
      }
    },
    {
      name     = "https"
      protocol = "HTTPS"
      port     = 443
      tls = {
        mode = "Terminate"
        certificate_ref = {
          name = "tls-secret"
        }
      }
    }
  ]

  # IPAM configuration
  enable_ipam = true
  ipam_selector = {
    pool = "external"
  }

  # Optional: Policy attachments
  security_policy_refs = [
    {
      name = "firewall-policy"
    }
  ]

  # Dependency
  gatewayclass_ready = module.bnk_gatewayclass.gatewayclass_ready

  common_labels = {
    environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Required | Default |
|------|-------------|------|----------|---------|
| cluster_name | EKS cluster name | string | yes | - |
| gateway_name | Gateway resource name | string | yes | - |
| gateway_namespace | Namespace for Gateway | string | yes | - |
| gatewayclass_name | BNKGatewayClass name | string | yes | - |
| listeners | List of listener configurations | list(object) | yes | - |
| addresses | Static addresses for Gateway | list(object) | no | [] |
| enable_ipam | Enable IPAM for IP allocation | bool | no | true |
| security_policy_refs | Security policy attachments | list(object) | no | [] |
| network_policy_refs | Network policy attachments | list(object) | no | [] |
| gatewayclass_ready | GatewayClass ready flag | bool | yes | - |

## Outputs

| Name | Description |
|------|-------------|
| gateway_name | Gateway resource name |
| gateway_namespace | Gateway namespace |
| gateway_ready | Ready flag for routes |
| listeners | Configured listeners |
| security_policies_attached | Number of security policies |
| network_policies_attached | Number of network policies |

## Listener Protocols

- **HTTP**: Plain HTTP traffic
- **HTTPS**: TLS-terminated HTTP traffic
- **TCP**: Layer 4 TCP traffic
- **UDP**: Layer 4 UDP traffic
- **TLS**: TLS passthrough

## TLS Configuration

### Terminate Mode (Default for HTTPS)
```hcl
tls = {
  mode = "Terminate"
  certificate_ref = {
    name      = "my-tls-secret"
    namespace = "cert-namespace" # optional
  }
}
```

### Passthrough Mode
```hcl
tls = {
  mode = "Passthrough"
}
```

## Allowed Routes

Control which routes can attach to listeners:

```hcl
allowed_routes = {
  namespaces = {
    from = "Same" # Same, All, Selector
  }
  kinds = [
    {
      group = "gateway.networking.k8s.io"
      kind  = "HTTPRoute"
    }
  ]
}
```

## Module Metadata

- **Category**: bnk
- **Workflow Compatibility**: Greenfield, Partial
- **Version**: 2.1.x
- **Last Updated**: 2025-11-22
