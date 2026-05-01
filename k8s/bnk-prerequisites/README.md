# BNK Prerequisites Module

## Overview

The first module in the BNK stack. Creates required namespaces, distributes FAR image pull secrets, downloads the BNK manifest from repo.f5.com, and parses component versions (FLO version, cert-manager version, etc.).

## What It Does

1. **Creates namespaces**: `f5-cne-core` (FLO, CWC, IPAM, Observer, OTEL) and `f5-bnk` (CNEInstance workloads — TMM, controller, VLANs, NADs)
2. **Creates FAR secrets**: Image pull secrets in both namespaces for `repo.f5.com` access
3. **Downloads BNK manifest**: From F5 Artifact Registry using the service account key
4. **Parses versions**: Extracts FLO Helm chart version and component versions from manifest
5. **Destroy cleanup**: Strips F5 finalizers and webhooks to prevent stuck resources

### Namespace Model (F5 BNK 2.2)

Per F5 BNK 2.2 documentation, the two-namespace model is:

- **`f5-cne-core`**: FLO operator and CNE core components (CWC, IPAM, RabbitMQ, Observer, OTEL)
- **`f5-bnk`** (configurable): CNEInstance workloads (TMM, CNE controller, VLANs, NADs)

## Dependencies

- **Kubernetes Cluster**: Running cluster with valid credentials
- No other BNK modules — this is the entry point

## Usage

```hcl
module "bnk_prerequisites" {
  source = "./k8s/bnk-prerequisites"

  # F5 service account key (project secret)
  cne_pull_secret = var.cne_pull_secret  # base64-encoded JSON

  # BNK manifest version
  bnk_manifest_version = "2.2.1-3.2226.0-0.0.511"

  # Namespace configuration (defaults match F5 BNK 2.2 docs)
  cne_core_namespace     = "f5-cne-core"
  cne_instance_namespace = "f5-bnk"

  # Cluster (auto-wired)
  cluster_name = module.eks.cluster_name
}
```

## Inputs

| Name | Description | Type | Required | Default |
|------|-------------|------|----------|---------|
| cne_pull_secret | Base64-encoded F5 FAR service account key | string (sensitive) | yes | - |
| bnk_manifest_version | BNK manifest version to download | string | no | "2.2.1-3.2226.0-0.0.511" |
| cne_core_namespace | Namespace for FLO + CNE core components | string | no | "f5-cne-core" |
| cne_instance_namespace | Namespace for CNEInstance workloads | string | no | "f5-bnk" |
| cluster_name | Kubernetes cluster name | string | no | "" |

## Outputs

| Name | Description |
|------|-------------|
| cne_core_namespace | CNE core namespace name |
| cne_instance_namespace | CNE instance namespace name |
| far_secret_name | FAR image pull secret name (always "far-secret") |
| flo_version | FLO Helm chart version (parsed from manifest) |
| manifest_version | BNK manifest version used |
| component_versions | All component versions from manifest |
| cert_manager_version | F5 cert-manager version (informational) |
| prerequisites_ready | Gate — true when all prerequisites are ready |

## Verification

```bash
# Check namespaces
kubectl get ns | grep -E "f5-cne-core|f5-bnk"

# Check FAR secrets exist in both namespaces
kubectl get secret far-secret -n f5-cne-core
kubectl get secret far-secret -n f5-bnk
```

## References

- [F5 BNK Installation](https://clouddocs.f5.com/bigip-next-for-kubernetes/latest/installing-bnk-dpu-using-f5-lifecycle-operator/installing/bnk-install-flo.html)

## Module Metadata

- **Category**: k8s
- **Workflow Compatibility**: Greenfield, Partial
- **Version**: 2.2.0
- **Last Updated**: 2026-04-29
