# BNK-Forge Module Dependency Graph

This document maps all module dependencies and their input/output relationships for automated root.hcl generation.

## Module Layers (FLO-Based Architecture)

```
┌─────────────────────────────────────────────────────────────┐
│                   BNK Application Layer                      │
│        bnk-secpolicy, bnk-netpolicy, routes                 │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│                   BNK Gateway Layer                          │
│              gateway, bnk-gatewayclass                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│                   BNK Platform Layer                         │
│                         flo                                  │
│    ┌─────────────────────────────────────────────────┐      │
│    │  FLO Auto-Deploys: CWC, DSSM, TMM, F5 Ingress,  │      │
│    │  Fluentd, CRDs, Observer, IPAM, RabbitMQ, etc.  │      │
│    └─────────────────────────────────────────────────┘      │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│                   BNK Foundation Layer                       │
│                       far-setup                              │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│                   Kubernetes Layer                           │
│              cert-manager, network-setup                     │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────────────────┐
│            Infrastructure Layer (AWS Example)                │
│    vpc → security → eks → storage → high-performance        │
└─────────────────────────────────────────────────────────────┘
```

## Key Architecture Change: FLO Manages BNK Components

As of BIG-IP Next for Kubernetes v2.1.0, the **F5 Lifecycle Operator (FLO)** automatically deploys and manages:

| Component | Previously | Now |
|-----------|------------|-----|
| CWC (Cluster Wide Controller) | Manual module | FLO auto-deploys |
| DSSM | Manual module | FLO auto-deploys |
| F5 Ingress | Manual module | FLO auto-deploys |
| Fluentd | Manual module | FLO auto-deploys |
| TMM | Manual module | FLO auto-deploys |
| CRDs (all) | Manual modules | FLO manages |
| Observer | Manual | FLO auto-deploys |
| IPAM Controller | Manual | FLO auto-deploys |
| RabbitMQ | Manual | FLO auto-deploys |

**Trigger**: When you apply a `BnkGatewayClass` CR, FLO deploys all required BNK components.

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
- **Required For**: BNK modules requiring persistent storage

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
- **Required For**: High-performance TMM pods (DPU/GPU nodes)

### Kubernetes Layer

#### k8s/cert-manager
- **Layer**: K8s Foundation
- **Dependencies**: far-setup (for FAR registry access)
- **Required Inputs**:
  - cluster_name
  - namespace
  - far_secret_name (from far-setup)
  - cert_manager_version
- **Key Outputs**: cert_manager_ready, release_status
- **Required For**: flo (prerequisite for webhook certificates)

#### k8s/network-setup
- **Layer**: K8s Foundation
- **Dependencies**: Kubernetes cluster
- **Required Inputs**:
  - cluster_name
  - namespace
  - external_subnet_cidrs (from vpc or user-provided)
  - internal_subnet_cidrs (from vpc or user-provided)
- **Key Outputs**: external_nad_name, internal_nad_name
- **Required For**: bnk-gatewayclass (network attachments for TMM pods)

### BNK Foundation Layer

#### bnk/far-setup
- **Layer**: BNK Foundation
- **Dependencies**: Kubernetes cluster (any)
- **Required Inputs**:
  - cluster_name
  - spk_manifest_version
  - service_account_key_file (user-provided FAR credentials)
- **Key Outputs**:
  - spk_namespace
  - utils_namespace
  - far_secret_name
  - setup_complete
- **Required For**: cert-manager, flo

### BNK Platform Layer

#### bnk/flo
- **Layer**: BNK Platform (Core Operator)
- **Dependencies**: far-setup, cert-manager
- **Required Inputs**:
  - cluster_name
  - flo_namespace
  - flo_version
  - far_secret_name (from far-setup)
  - far_setup_complete (from far-setup)
  - cert_manager_ready (from cert-manager)
  - license_mode (connected|disconnected)
  - jwt_token (for licensing, if connected mode)
- **Key Outputs**:
  - flo_ready
  - flo_namespace
  - crds_installed (FLO manages all CRDs)
  - license_mode
- **What FLO Auto-Deploys**:
  - CWC (Cluster Wide Controller)
  - DSSM (Distributed Session State Manager)
  - TMM (Traffic Management Microkernel)
  - F5 Ingress
  - Fluentd (logging)
  - All CRDs
  - Observer
  - IPAM Controller (if enabled)
  - RabbitMQ
  - OTEL Collector
- **Required For**: bnk-gatewayclass, gateway, routes, policies

### BNK Gateway Layer

#### bnk/bnk-gatewayclass
- **Layer**: BNK Gateway
- **Dependencies**: flo
- **Required Inputs**:
  - cluster_name
  - gatewayclass_name
  - flo_namespace (from flo)
  - flo_ready (from flo)
  - tmm_resource_limits (CPU, memory, hugepages)
  - network_attachments (from network-setup or user-provided)
- **Key Outputs**:
  - gatewayclass_name
  - gatewayclass_ready
- **Trigger**: Applying BnkGatewayClass CR triggers FLO to deploy all BNK components
- **Required For**: gateway

#### bnk/gateway
- **Layer**: BNK Gateway
- **Dependencies**: bnk-gatewayclass
- **Required Inputs**:
  - cluster_name
  - gateway_name
  - gateway_namespace
  - gatewayclass_name (from bnk-gatewayclass)
  - gatewayclass_ready (from bnk-gatewayclass)
  - listeners (user-provided)
- **Key Outputs**:
  - gateway_name
  - gateway_ready
  - gateway_addresses
- **Required For**: routes

### BNK Application Layer

#### bnk/routes
- **Layer**: BNK Application
- **Dependencies**: gateway
- **Required Inputs**:
  - cluster_name
  - route_name
  - route_namespace
  - gateway_name (from gateway)
  - gateway_ready (from gateway)
  - route_type (HTTPRoute, GRPCRoute, L4Route)
  - routing_rules (user-provided)
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
  - security_settings (firewall, DDoS, rate limiting, ACL)
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
  - network_settings (TCP profiles, HTTP profiles, logging, persistence)
- **Key Outputs**: policy_ready
- **Required For**: Gateway/Route attachment (optional)

## Workflow Patterns

### Pattern 1: Full AWS + BNK Gateway API Stack (Recommended)
```
vpc → security → eks → storage → far-setup → cert-manager → network-setup → flo → bnk-gatewayclass → gateway → routes
                                                                                   └→ bnk-secpolicy
                                                                                   └→ bnk-netpolicy
```

### Pattern 2: Existing K8s + BNK Gateway API
```
(existing K8s) → far-setup → cert-manager → network-setup → flo → bnk-gatewayclass → gateway → routes
```

### Pattern 3: Minimal BNK Deployment
```
far-setup → cert-manager → flo → bnk-gatewayclass → gateway → routes
```

### Pattern 4: BNK with High-Performance Nodes (DPU)
```
vpc → security → eks → high-performance-nodes → far-setup → cert-manager → network-setup → flo → bnk-gatewayclass → gateway
```

## Entry Points by User Scenario

### Scenario A: "I have nothing, deploy everything on AWS"
**Entry Point**: vpc
**Full Chain**: vpc → security → eks → storage → far-setup → cert-manager → network-setup → flo → bnk-gatewayclass → gateway → routes

### Scenario B: "I have AWS EKS, add BNK"
**Entry Point**: far-setup
**Chain**: far-setup → cert-manager → network-setup → flo → bnk-gatewayclass → gateway → routes

### Scenario C: "I have Kubernetes (any provider), add BNK"
**Entry Point**: far-setup
**Chain**: far-setup → cert-manager → flo → bnk-gatewayclass → gateway → routes

### Scenario D: "I have FLO installed, configure traffic"
**Entry Point**: bnk-gatewayclass
**Chain**: bnk-gatewayclass → gateway → routes

## Auto-Dependency Resolution Rules

1. **Required dependencies MUST be auto-included** (shown in error if not)
2. **Optional dependencies SHOULD be suggested** (user can skip)
3. **Infrastructure layer can be skipped** if user provides cluster access
4. **User selects entry point**, system resolves forward dependencies
5. **Backward dependencies auto-detected** from module metadata
6. **FLO is the central orchestrator** - selecting any Gateway API module requires FLO

## Archived Modules (Managed by FLO)

The following modules have been archived as they are now automatically deployed by FLO:

| Archived Module | Replaced By |
|-----------------|-------------|
| `bnk/cwc` | FLO auto-deploys |
| `bnk/dssm` | FLO auto-deploys |
| `bnk/fluentd` | FLO auto-deploys |
| `bnk/f5-controller` | FLO auto-deploys (F5 Ingress) |
| `bnk/crds/common` | FLO manages |
| `bnk/crds/deprecated` | FLO manages |
| `bnk/crds/service-proxy` | FLO manages |

See `archived/README.md` for details.
