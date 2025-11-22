# BNKGatewayClass Module

## Overview

Creates a BNKGatewayClass resource for BIG-IP Next for Kubernetes using the standard Kubernetes Gateway API. The GatewayClass defines the infrastructure class of Gateways managed by the F5 controller.

## Features

- Standard Kubernetes Gateway API compliance
- Default TMM (Traffic Management Microkernel) configuration
- High availability support with pod anti-affinity
- IPAM integration for automatic IP allocation
- Configurable resource requests and limits
- Network attachment definitions for multi-NIC TMM pods

## Dependencies

- **FLO**: F5 Lifecycle Operator must be installed (installs Gateway API CRDs)
- **F5 Controller**: F5 ingress/gateway controller

## Usage

```hcl
module "bnk_gatewayclass" {
  source = "./bnk/bnk-gatewayclass"

  # Cluster configuration
  cluster_name = "my-eks-cluster"

  # GatewayClass configuration
  gatewayclass_name = "bnk-gatewayclass"
  controller_name   = "f5.com/gateway-controller"

  # Namespaces
  flo_namespace        = "f5-operators"
  controller_namespace = "f5-spk"

  # TMM defaults
  default_tmm_replicas    = 2
  default_tmm_cpu         = "2"
  default_tmm_memory      = "4Gi"
  default_tmm_hugepages_2mi = "1Gi"

  # High availability
  enable_ha              = true
  anti_affinity_enabled  = true

  # Service configuration
  default_service_type = "LoadBalancer"
  enable_ipam          = true
  ipam_namespace       = "f5-ipam"

  # Network attachments
  network_attachments = {
    external = "external-network"
    internal = "internal-network"
  }

  # Dependency
  flo_ready = module.flo.flo_ready

  common_labels = {
    environment = "production"
  }
}
```

## Inputs

| Name | Description | Type | Required | Default |
|------|-------------|------|----------|---------|
| cluster_name | EKS cluster name | string | yes | - |
| gatewayclass_name | BNKGatewayClass name | string | no | "bnk-gatewayclass" |
| controller_name | F5 controller name | string | no | "f5.com/gateway-controller" |
| flo_namespace | FLO namespace (GatewayClass must be here) | string | yes | - |
| controller_namespace | F5 controller namespace | string | yes | - |
| default_tmm_replicas | Default TMM replica count | number | no | 2 |
| enable_ha | Enable high availability | bool | no | true |
| enable_ipam | Enable IPAM for services | bool | no | true |
| flo_ready | FLO ready flag | bool | yes | - |

## Outputs

| Name | Description |
|------|-------------|
| gatewayclass_name | BNKGatewayClass resource name |
| gatewayclass_controller | Controller managing this class |
| gatewayclass_ready | Ready flag for dependent modules |
| config_name | BNKGatewayClassConfig name |
| default_tmm_replicas | Configured default replica count |
| ipam_enabled | IPAM enabled status |

## Gateway API Resources

This module creates:
1. **GatewayClass**: Cluster-scoped resource defining infrastructure class
2. **BNKGatewayClassConfig**: F5-specific configuration parameters

Subsequent Gateway resources reference this GatewayClass:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
spec:
  gatewayClassName: bnk-gatewayclass  # References this module
  listeners: [...]
```

## Module Metadata

- **Category**: bnk
- **Workflow Compatibility**: Greenfield, Partial
- **Version**: 2.1.x
- **Last Updated**: 2025-11-22
