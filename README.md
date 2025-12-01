# BNK-Forge Official Module Library

This repository contains the official BNK-Forge module library - a curated collection of Terraform/Terragrunt modules for deploying infrastructure, Kubernetes prerequisites, and BIG-IP Next for Kubernetes (BNK) components.

## Overview

This is a **read-only reference library** that is synced into the BNK-Forge tool. Users select modules from this catalog through the BNK-Forge UI, which then generates their customized project in `bnk-forge-live`.

## Repository Structure

```
bnk-forge-modules/
├── infra/                    # Infrastructure modules
│   └── aws/
│       ├── vpc/              # AWS VPC with public/private subnets
│       ├── eks/              # Amazon EKS cluster
│       ├── security/         # Security groups and IAM
│       ├── storage/          # S3, EFS storage
│       └── high-performance-nodes/  # DPU/GPU node pools
├── k8s/                      # Kubernetes prerequisite modules
│   ├── cert-manager/         # F5 cert-manager (TLS certificates)
│   └── network-setup/        # Multus CNI network attachments
├── bnk/                      # BIG-IP Next for Kubernetes modules
│   ├── far-setup/            # FAR image pull secrets (prerequisite)
│   ├── flo/                  # F5 Lifecycle Operator
│   ├── bnk-gatewayclass/     # BnkGatewayClass CR (triggers FLO deployment)
│   ├── gateway/              # Gateway API Gateway resources
│   ├── routes/               # HTTPRoute, GRPCRoute, L4Route
│   ├── bnk-netpolicy/        # Network policies (TCP, HTTP, logging)
│   └── bnk-secpolicy/        # Security policies (firewall, DDoS, ACL)
├── archived/                 # Deprecated modules (managed by FLO)
└── templates/                # Module templates
```

## BNK Deployment Flow (v2.1.0+)

With F5 Lifecycle Operator (FLO), many components are now deployed automatically:

### 1. Prerequisites
| Module | Purpose |
|--------|---------|
| `k8s/cert-manager` | TLS certificate management |
| `k8s/network-setup` | Multus CNI network attachments |
| `bnk/far-setup` | FAR image pull secrets for repo.f5.com |

### 2. FLO Deployment
| Module | Purpose |
|--------|---------|
| `bnk/flo` | Deploys F5 Lifecycle Operator via Helm |

### 3. BNK Components (FLO Auto-Deploys)
When you apply a `BnkGatewayClass` CR, FLO automatically deploys:
- CWC (Cluster Wide Controller)
- DSSM (Distributed Session State Manager)
- TMM (Traffic Management Microkernel)
- F5 Ingress
- Fluentd
- All CRDs
- And more...

| Module | Purpose |
|--------|---------|
| `bnk/bnk-gatewayclass` | Creates BnkGatewayClass CR to trigger FLO |

### 4. Traffic Configuration
| Module | Purpose |
|--------|---------|
| `bnk/gateway` | Gateway resources for traffic entry points |
| `bnk/routes` | HTTPRoute, GRPCRoute, L4Route for routing |
| `bnk/bnk-netpolicy` | Network policies (TCP profiles, logging) |
| `bnk/bnk-secpolicy` | Security policies (firewall, DDoS, rate limiting) |

## Module Categories

### Infrastructure (infra)
Cloud infrastructure components - networks, compute, databases
- **Workflow Compatibility**: Greenfield only
- **Providers**: AWS (Azure, GCP planned)

### Kubernetes (k8s)
Kubernetes cluster prerequisites and add-ons
- **Workflow Compatibility**: Greenfield, Partial
- **Providers**: Cloud-agnostic

### BNK Applications (bnk)
BIG-IP Next for Kubernetes components
- **Workflow Compatibility**: Greenfield, Partial, Minimal
- **Providers**: Cloud-agnostic (requires Kubernetes)

## Archived Modules

Some modules have been archived as they are now managed by FLO:
- `cwc`, `dssm`, `fluentd`, `f5-controller`
- `crds/common`, `crds/deprecated`, `crds/service-proxy`

See `archived/README.md` for details.

## Module Standards

Each module includes:
- `main.tf` - Terraform resources
- `variables.tf` - Input variables
- `outputs.tf` - Output values
- `versions.tf` - Provider requirements
- `module.json` - BNK-Forge metadata
- `README.md` - Documentation

## Usage

**Do not clone or modify this repository directly.**

Users interact through BNK-Forge UI:
1. Select modules from the catalog
2. Configure variables
3. BNK-Forge generates project in `bnk-forge-live`
4. Deploy with Terragrunt

## Reference Documentation

- [F5 Lifecycle Operator](https://clouddocs.f5.com/bigip-next-for-kubernetes/latest/bnk-f5-lifecycle-operator.html)
- [BIG-IP Next for Kubernetes CRDs](https://clouddocs.f5.com/bigip-next-for-kubernetes/latest/spk-custom-resources.html)
- [Gateway API](https://gateway-api.sigs.k8s.io/)

## Related Repositories

- **bnk-forge**: Main BNK-Forge application
- **bnk-forge-live**: User deployment projects

---

For more information, see the [BNK-Forge Documentation](https://github.com/JLCode-tech/bnk-forge)
