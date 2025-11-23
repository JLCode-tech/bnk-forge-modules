# BNK-Forge Module Dependency Graph

This document maps all module dependencies and their input/output relationships for automated root.hcl generation.

## Module Layers

```
┌─────────────────────────────────────────────────────────────┐
│                      BNK Application Layer                   │
│  bnk-secpolicy, bnk-netpolicy, routes, gateway              │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│                   BNK Gateway Layer                          │
│     bnk-gatewayclass, gateway, routes                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│                   BNK Platform Layer                         │
│     flo, cwc, dssm, f5-controller, fluentd                  │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│                   BNK Foundation Layer                       │
│     far-setup, crds (common, service-proxy, deprecated)     │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│                   Kubernetes Layer                           │
│          cert-manager, network-setup                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│            Infrastructure Layer (AWS Example)                │
│    vpc → security → eks → storage → high-performance        │
└─────────────────────────────────────────────────────────────┘
```

## Detailed Module Dependencies

### Infrastructure Layer (AWS)

#### infra/aws/vpc
- **Layer**: Foundation
- **Dependencies**: None
- **Required Inputs**: project_name, environment, vpc_cidr, subnet_cidrs
- **Key Outputs**: vpc_id, vpc_cidr_block, subnet_ids, availability_zones
- **Required For**: security, eks, storage, high-performance-nodes

#### infra/aws/security
- **Layer**: Foundation
- **Dependencies**: vpc
- **Required Inputs**: vpc_id (from vpc), vpc_cidr_block (from vpc), public_subnet_id (from vpc), user_ip
- **Key Outputs**:
  - infrastructure_key_name
  - vpc_security_group_id
  - eks_cluster_role_arn
  - nodegroup_role_arn
  - jumphost_public_ip
  - oidc_provider_arn (conditional)
- **Required For**: eks, high-performance-nodes

#### infra/aws/eks
- **Layer**: Platform
- **Dependencies**: vpc, security
- **Required Inputs**:
  - vpc_id (from vpc)
  - private_external_subnet_ids (from vpc)
  - private_internal_subnet_ids (from vpc)
  - eks_cluster_role_arn (from security)
  - nodegroup_role_arn (from security)
  - vpc_security_group_id (from security)
  - infrastructure_key_name (from security)
- **Key Outputs**:
  - cluster_name
  - cluster_endpoint
  - cluster_certificate_authority_data
  - oidc_provider_arn
  - kubectl_config_command
- **Required For**: storage, high-performance-nodes, ALL k8s and BNK modules

#### infra/aws/storage
- **Layer**: Platform
- **Dependencies**: eks
- **Required Inputs**: cluster_name (from eks)
- **Key Outputs**: storage_classes_deployed, storage_class_names
- **Required For**: BNK modules requiring persistent storage (dssm, fluentd)

#### infra/aws/high-performance-nodes
- **Layer**: Platform
- **Dependencies**: vpc, security, eks
- **Required Inputs**:
  - vpc_id (from vpc)
  - cluster_name (from eks)
  - vpc_security_group_id (from security)
  - nodegroup_role_arn (from security)
  - key_pair_name (from security)
- **Key Outputs**: nodegroup_name, nodegroup_status
- **Required For**: f5-controller (if using high-performance nodes)

### Kubernetes Layer

#### k8s/cert-manager
- **Layer**: K8s Foundation
- **Dependencies**: far-setup (BNK), OR standalone K8s cluster
- **Required Inputs**:
  - cluster_name
  - namespace (from far-setup)
  - far_secret_name (from far-setup)
  - cert_manager_version (from far-setup)
- **Key Outputs**: cert_manager_ready, release_status
- **Required For**: cwc, flo (recommended)

#### k8s/network-setup
- **Layer**: K8s Foundation
- **Dependencies**: Kubernetes cluster
- **Required Inputs**:
  - cluster_name
  - namespace
  - external_subnet_cidrs (from vpc or user-provided)
  - internal_subnet_cidrs (from vpc or user-provided)
- **Key Outputs**: external_nad_name, internal_nad_name
- **Required For**: f5-controller (if using network attachments)

### BNK Foundation Layer

#### bnk/far-setup
- **Layer**: BNK Foundation
- **Dependencies**: Kubernetes cluster (any)
- **Required Inputs**:
  - cluster_name
  - spk_manifest_version
  - service_account_key_file (user-provided)
- **Key Outputs**:
  - spk_namespace
  - utils_namespace
  - far_secret_name
  - cert_manager_version
  - cwc_version
  - controller_version
  - dssm_version
  - fluentd_version
  - crds_versions
  - setup_complete
- **Required For**: ALL BNK modules

#### bnk/crds/common
- **Layer**: BNK Foundation
- **Dependencies**: far-setup
- **Required Inputs**:
  - cluster_name
  - crd_common_version (from far-setup)
  - far_setup_complete (from far-setup)
- **Key Outputs**: crds_ready
- **Required For**: Most BNK modules

#### bnk/crds/service-proxy
- **Layer**: BNK Foundation
- **Dependencies**: far-setup
- **Required Inputs**:
  - cluster_name
  - crd_service_proxy_version (from far-setup)
  - far_setup_complete (from far-setup)
- **Key Outputs**: crds_ready
- **Required For**: f5-controller, flo

#### bnk/crds/deprecated
- **Layer**: BNK Foundation (Optional)
- **Dependencies**: far-setup
- **Required Inputs**:
  - cluster_name
  - crd_deprecated_version (from far-setup)
  - far_setup_complete (from far-setup)
- **Key Outputs**: crds_ready
- **Required For**: Legacy BNK deployments only

### BNK Platform Layer

#### bnk/flo
- **Layer**: BNK Platform Core
- **Dependencies**: far-setup, cert-manager (optional), crds
- **Required Inputs**:
  - cluster_name
  - flo_namespace (from far-setup)
  - flo_version
  - far_secret_name (from far-setup)
  - license_mode
  - cert_manager_ready (optional, from cert-manager)
- **Key Outputs**:
  - flo_ready
  - flo_namespace
  - crds_installed
  - license_mode
- **Required For**: ALL BNK Gateway API modules (bnk-gatewayclass, gateway, routes, policies)

#### bnk/dssm
- **Layer**: BNK Platform
- **Dependencies**: far-setup, storage
- **Required Inputs**:
  - namespace (from far-setup)
  - dssm_version (from far-setup)
  - far_secret_name (from far-setup)
  - storage_class (from storage or user-provided)
- **Key Outputs**:
  - dssm_ready
  - sentinel_service_host
  - sentinel_service_port
- **Required For**: f5-controller

#### bnk/cwc
- **Layer**: BNK Platform
- **Dependencies**: far-setup, cert-manager
- **Required Inputs**:
  - cluster_name
  - namespace (from far-setup)
  - cwc_version (from far-setup)
  - rabbitmq_version (from far-setup)
  - far_secret_name (from far-setup)
  - storage_class
  - cert_manager_ready (from cert-manager)
  - license_environment
  - connected_mode
- **Key Outputs**: cwc_ready, rabbitmq_ready
- **Required For**: Multi-cluster deployments (optional for single cluster)

#### bnk/fluentd
- **Layer**: BNK Platform
- **Dependencies**: far-setup, storage
- **Required Inputs**:
  - cluster_name
  - namespace (from far-setup)
  - fluentd_version (from far-setup)
  - far_secret_name (from far-setup)
  - storage_class
  - far_setup_complete (from far-setup)
  - cert_manager_complete (optional)
- **Key Outputs**:
  - fluentd_ready
  - fluentd_service_host
  - fluentd_service_port
- **Required For**: f5-controller (optional for logging)

#### bnk/f5-controller
- **Layer**: BNK Platform (SPK Controller)
- **Dependencies**: far-setup, dssm, network-setup (optional)
- **Required Inputs**:
  - cluster_name
  - f5_spk_namespace (from far-setup)
  - rabbitmq_namespace (from far-setup)
  - f5_controller_chart_version (from far-setup)
  - far_secret_name (from far-setup)
  - dssm_sentinel_host (from dssm)
  - dssm_sentinel_port (from dssm)
  - external_nad_name (from network-setup or user-provided)
  - internal_nad_name (from network-setup or user-provided)
  - f5_vlan_ips
- **Key Outputs**: controller_ready, tmm_ready
- **Required For**: Legacy ingress mode (not required for Gateway API)

### BNK Gateway API Layer

#### bnk/bnk-gatewayclass
- **Layer**: BNK Gateway
- **Dependencies**: flo
- **Required Inputs**:
  - cluster_name
  - gatewayclass_name
  - flo_namespace (from flo)
  - flo_ready (from flo)
  - tmm_resource_limits (CPU, memory)
- **Key Outputs**:
  - gatewayclass_name
  - gatewayclass_ready
- **Required For**: gateway

#### bnk/gateway
- **Layer**: BNK Gateway
- **Dependencies**: bnk-gatewayclass
- **Required Inputs**:
  - cluster_name
  - gateway_name
  - gateway_namespace
  - gatewayclass_name (from bnk-gatewayclass)
  - listeners (user-provided)
  - flo_ready (from flo)
- **Key Outputs**:
  - gateway_name
  - gateway_ready
  - gateway_addresses
- **Required For**: routes

#### bnk/routes
- **Layer**: BNK Application
- **Dependencies**: gateway
- **Required Inputs**:
  - cluster_name
  - route_name
  - route_namespace
  - gateway_name (from gateway)
  - route_type (HTTPRoute, GRPCRoute, L4Route)
  - routing_rules (user-provided)
  - flo_ready (from flo)
- **Key Outputs**: route_ready, route_name
- **Required For**: Application traffic routing

### BNK Policy Layer

#### bnk/bnk-secpolicy
- **Layer**: BNK Policy
- **Dependencies**: flo
- **Required Inputs**:
  - cluster_name
  - policy_name
  - policy_namespace
  - flo_ready (from flo)
  - security_settings (user-provided)
- **Key Outputs**: policy_ready
- **Required For**: Gateway/Route attachment (optional)

#### bnk/bnk-netpolicy
- **Layer**: BNK Policy
- **Dependencies**: flo
- **Required Inputs**:
  - cluster_name
  - policy_name
  - policy_namespace
  - flo_ready (from flo)
  - network_settings (user-provided)
- **Key Outputs**: policy_ready
- **Required For**: Gateway/Route attachment (optional)

## Common Workflow Patterns

### Pattern 1: Full AWS + BNK Gateway API Stack
```
vpc → security → eks → storage → far-setup → cert-manager → flo → bnk-gatewayclass → gateway → routes
                                                                  └→ bnk-secpolicy
                                                                  └→ bnk-netpolicy
```

### Pattern 2: Existing K8s + BNK Gateway API
```
(existing K8s) → far-setup → cert-manager → flo → bnk-gatewayclass → gateway → routes
```

### Pattern 3: Full AWS + Legacy SPK Controller
```
vpc → security → eks → storage → network-setup → far-setup → cert-manager → dssm → f5-controller
                                                            └→ fluentd
```

### Pattern 4: BNK Gateway API Only (Minimal)
```
far-setup → flo → bnk-gatewayclass → gateway → routes
```

## Entry Points by User Scenario

### Scenario A: "I have nothing, deploy everything on AWS"
**Entry Point**: vpc
**Full Chain**: vpc → security → eks → storage → far-setup → cert-manager → flo → bnk-gatewayclass → gateway → routes

### Scenario B: "I have AWS EKS, add BNK"
**Entry Point**: far-setup
**Chain**: far-setup → cert-manager → flo → bnk-gatewayclass → gateway → routes

### Scenario C: "I have Kubernetes (any), add BNK"
**Entry Point**: far-setup
**Chain**: far-setup → cert-manager → flo → bnk-gatewayclass → gateway → routes

### Scenario D: "I have BNK, just add Gateway API routing"
**Entry Point**: bnk-gatewayclass
**Chain**: bnk-gatewayclass → gateway → routes

### Scenario E: "I want legacy SPK Controller mode"
**Entry Point**: far-setup
**Chain**: far-setup → cert-manager → network-setup → dssm → f5-controller

## Auto-Dependency Resolution Rules

1. **Required dependencies MUST be auto-included** (shown in error if not)
2. **Optional dependencies SHOULD be suggested** (user can skip)
3. **Infrastructure layer can be skipped** if user provides cluster access
4. **User selects entry point**, system resolves forward dependencies
5. **Backward dependencies auto-detected** from module metadata
