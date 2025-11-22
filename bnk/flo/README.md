# F5 Lifecycle Operator (FLO) Module

## Overview

Deploys the F5 Lifecycle Operator (FLO) via Helm chart from F5 Artifact Registry (FAR). FLO is the core operator that manages the lifecycle of BIG-IP Next for Kubernetes components.

## What FLO Installs

FLO automatically deploys the following components:
- **IPAM Operator**: IP Address Management for Kubernetes services
- **BnkGatewayClass CRD**: Gateway API custom resource definition
- **Component CRDs**: All BIG-IP Next for Kubernetes custom resource definitions

## Features

- Automatic CRD installation and management
- Integrated licensing (connected mode or F5 License Proxy)
- IPAM operator deployment
- Support for production and test environments
- Configurable resource requests/limits
- Node selector and toleration support

## Dependencies

- **EKS Cluster**: Running Kubernetes cluster
- **cert-manager**: Certificate management (must be installed first)
- **FAR Setup**: F5 Artifact Registry access and pull secrets

## Usage

```hcl
module "flo" {
  source = "./bnk/flo"

  # Cluster configuration
  cluster_name = "my-eks-cluster"

  # Namespaces
  flo_namespace  = "f5-operators"
  ipam_namespace = "f5-ipam"

  # FAR configuration
  far_secret_name = "f5-far-secret"
  flo_version     = "v1.198.4-0.1.36"

  # Licensing configuration
  license_mode        = "connected"
  license_environment = "production"
  jwt_token           = var.f5_jwt_token # sensitive

  # Image registry
  image_registry = "repo.f5.com/images"

  # Dependencies
  cert_manager_ready = module.cert_manager.ready
  far_setup_complete = module.far_setup.setup_complete

  # Optional: Resource configuration
  flo_cpu_request    = "100m"
  flo_memory_request = "128Mi"
  flo_cpu_limit      = "500m"
  flo_memory_limit   = "512Mi"

  # Optional: Node placement
  node_selector = {
    "node-type" = "management"
  }

  common_tags = {
    Environment = "production"
    Project     = "my-project"
  }
}
```

## Licensing Modes

### Connected Mode (Default)
Connects directly to F5 licensing servers:
```hcl
license_mode        = "connected"
license_environment = "production" # or "test"
jwt_token           = "your-jwt-token"
```

### F5 License Proxy Mode
Uses an on-premises license proxy:
```hcl
license_mode          = "f5licenseproxy"
f5_license_proxy_url = "https://your-license-proxy:8080"
```

## Inputs

| Name | Description | Type | Required | Default |
|------|-------------|------|----------|---------|
| cluster_name | EKS cluster name | string | yes | - |
| flo_namespace | Namespace for FLO deployment | string | no | "f5-operators" |
| far_secret_name | FAR pull secret name | string | yes | - |
| flo_version | FLO Helm chart version | string | no | "v1.198.4-0.1.36" |
| license_mode | Licensing mode (connected/f5licenseproxy) | string | no | "connected" |
| license_environment | License environment (production/test) | string | no | "production" |
| jwt_token | JWT token for licensing | string (sensitive) | no | "" |
| cert_manager_ready | Cert-manager ready flag | bool | yes | - |
| far_setup_complete | FAR setup complete flag | bool | yes | - |

## Outputs

| Name | Description |
|------|-------------|
| flo_namespace | Namespace where FLO is deployed |
| ipam_namespace | Namespace where IPAM operator is deployed |
| flo_ready | Flag indicating FLO is ready |
| crds_installed | Flag indicating CRDs are installed |
| helm_release_name | Helm release name |
| helm_release_version | Helm chart version deployed |
| license_mode | Configured licensing mode |

## Deployment Order

1. VPC
2. Security (IAM roles, SSH keys, security groups)
3. EKS
4. Storage
5. **FAR Setup** (F5 Artifact Registry access)
6. **cert-manager** (Certificate management)
7. **→ FLO** (This module - manages CRDs)
8. CWC (Cluster Wide Controller)
9. dSSM (Distributed state)
10. F5 Controller (Ingress/Gateway)

## Notes

- FLO must be installed in a dedicated namespace (default: `f5-operators`)
- FLO automatically installs all required CRDs
- BNKGatewayClass CR must be created in the same namespace as FLO
- CRDs persist after FLO Helm uninstallation
- IPAM operator is deployed automatically unless disabled

## Verification

After deployment, verify FLO is running:
```bash
# Check FLO pods
kubectl get pods -n f5-operators

# Check IPAM pods
kubectl get pods -n f5-ipam

# Verify CRDs installed
kubectl get crd | grep gateway
kubectl get crd | grep f5
```

## Troubleshooting

**FLO pod not starting:**
- Verify cert-manager is running: `kubectl get pods -n cert-manager`
- Check FAR secret exists: `kubectl get secret f5-far-secret -n f5-operators`
- Review FLO logs: `kubectl logs -n f5-operators -l app=flo`

**License errors:**
- For connected mode: Verify JWT token is valid
- For proxy mode: Verify F5 License Proxy URL is accessible
- Check license configuration: `kubectl describe pod -n f5-operators -l app=flo`

## References

- [F5 Lifecycle Operator Documentation](https://clouddocs.f5.com/bigip-next-for-kubernetes/latest/bnk-install-flo.html)
- [F5 Licensing Guide](https://clouddocs.f5.com/bigip-next-for-kubernetes/latest/bnk-licensing.html)

## Module Metadata

- **Category**: bnk
- **Workflow Compatibility**: Greenfield, Partial, Minimal
- **Version**: 2.1.x
- **Last Updated**: 2025-11-22
