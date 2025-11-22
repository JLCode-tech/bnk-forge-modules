# Routes Module

## Overview

Creates routing rules for Gateways using the Kubernetes Gateway API. Supports HTTPRoute, GRPCRoute, and F5's L4Route for layer 4 traffic.

## Features

- Standard Gateway API HTTPRoute and GRPCRoute
- F5 L4Route extension for TCP/UDP traffic
- Path-based routing
- Header-based routing
- Request/response header modification
- URL rewriting and redirects
- Traffic splitting and canary deployments
- Session affinity (L4Route)

## Dependencies

- **Gateway**: Gateway instance must exist

## Usage Examples

### HTTPRoute Example
```hcl
module "http_route" {
  source = "./bnk/routes"

  cluster_name     = "my-eks-cluster"
  route_name       = "my-http-route"
  route_namespace  = "default"
  route_type       = "HTTPRoute"

  parent_refs = [
    {
      name         = "my-gateway"
      section_name = "http" # Listener name
    }
  ]

  hostnames = ["example.com", "www.example.com"]

  rules = [
    {
      matches = [
        {
          path = {
            type  = "PathPrefix"
            value = "/api"
          }
        }
      ]
      backend_refs = [
        {
          name = "api-service"
          port = 8080
        }
      ]
    }
  ]

  gateway_ready = module.gateway.gateway_ready
}
```

### GRPCRoute Example
```hcl
module "grpc_route" {
  source = "./bnk/routes"

  cluster_name     = "my-eks-cluster"
  route_name       = "my-grpc-route"
  route_namespace  = "default"
  route_type       = "GRPCRoute"

  parent_refs = [
    {
      name         = "my-gateway"
      section_name = "grpc"
    }
  ]

  hostnames = ["grpc.example.com"]

  rules = [
    {
      matches = [
        {
          method = "com.example.Service/Method"
        }
      ]
      backend_refs = [
        {
          name = "grpc-service"
          port = 9090
        }
      ]
    }
  ]

  gateway_ready = module.gateway.gateway_ready
}
```

### L4Route Example (F5 Extension)
```hcl
module "l4_route" {
  source = "./bnk/routes"

  cluster_name     = "my-eks-cluster"
  route_name       = "my-l4-route"
  route_namespace  = "default"
  route_type       = "L4Route"

  parent_refs = [
    {
      name = "my-gateway"
      port = 3306
    }
  ]

  l4_protocol = "TCP"

  l4_backend_refs = [
    {
      name   = "mysql-primary"
      port   = 3306
      weight = 80
    },
    {
      name   = "mysql-replica"
      port   = 3306
      weight = 20
    }
  ]

  session_affinity = {
    enabled = true
    timeout = "3600s"
  }

  gateway_ready = module.gateway.gateway_ready
}
```

### Traffic Splitting (Canary)
```hcl
rules = [
  {
    backend_refs = [
      {
        name   = "app-v1"
        port   = 8080
        weight = 90
      },
      {
        name   = "app-v2"
        port   = 8080
        weight = 10
      }
    ]
  }
]
```

### Header Modification
```hcl
rules = [
  {
    filters = [
      {
        type = "RequestHeaderModifier"
        request_header_modifier = {
          add = [
            {
              name  = "X-Custom-Header"
              value = "custom-value"
            }
          ]
          remove = ["X-Old-Header"]
        }
      }
    ]
    backend_refs = [...]
  }
]
```

## Module Metadata

- **Category**: bnk
- **Workflow Compatibility**: Greenfield, Partial
- **Version**: 2.1.x
- **Last Updated**: 2025-11-22
