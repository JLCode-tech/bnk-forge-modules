# bnk-forge-modules

Original Forge module library for **BNK 2.2 GA**. This is the repository that Forge installations have historically pointed at via `module_library.git_url` — and the one most existing customers still consume.

> **If you're standing up a new Forge installation today**, you may also want to look at the per-target catalog repos described under [The catalog ecosystem](#the-catalog-ecosystem) — those are where the AWS / IBM / Azure / GCP / on-prem deployment content is consolidating. This repo continues to host the BNK 2.2 GA reference content unchanged.

## Configure Forge to use this library

In Forge → **Settings → Defaults**:

```
Module Library Git URL: https://github.com/JLCode-tech/bnk-forge-modules.git
Module Library Git Ref: release/2.2
```

Then sync the catalog at **Settings → Environment Config → Sync Modules**.

`release/2.2` matches BNK 2.2 GA. `main` mirrors the latest stable release branch.

## What's in this repo

The full 14-module BNK 2.2 deployment stack (AWS infrastructure → Kubernetes prerequisites → BNK platform → Gateway API), plus a reference demo app stack.

| Family | Path | What it covers |
|---|---|---|
| Infrastructure (AWS) | `infra/aws/` | VPC, EKS, security/IAM, storage, high-performance nodes (SR-IOV + DPDK + Multus) |
| Kubernetes prerequisites | `k8s/` | `bnk-prerequisites`, `cert-manager`, `network-setup`, `bnk-cert-issuer` |
| BNK platform | `bnk/` | `flo`, `cneinstance`, `bnk-vlans`, `bnk-gatewayclass`, `gateway`, `routes`, `bnk-netpolicy`, `bnk-secpolicy`, etc. |
| Demo apps | `app/` | Reference demo stack including GenAI Bedrock proxy + analyzer |

The full module inventory and which entries are `active` / `legacy` / `deprecated` lives in [`catalog/releases/release-2.2-official.json`](./catalog/releases/release-2.2-official.json).

## BNK 2.2 deployment flow

```
infra/aws/vpc + security + eks + storage + high-performance-nodes
    └─→ k8s/bnk-prerequisites
            └─→ k8s/cert-manager + k8s/network-setup
                    └─→ bnk/flo
                            └─→ bnk/cneinstance + bnk/bnk-vlans
                                    └─→ bnk/bnk-gatewayclass
                                            └─→ bnk/gateway + bnk/routes
```

When CNEInstance + GatewayClass apply, FLO automatically deploys CWC, DSSM, TMM, F5 Ingress, Fluentd, Observer, OTEL, RabbitMQ, and all CRDs — none of those are separate modules.

## Module standards

Each module ships with:

- `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` — Terraform/OpenTofu sources
- `bnkforge.pack.json` — modern v2alpha1 Forge contract
- `module.json` — legacy schema (retained through the 2.2 lifecycle for backwards compatibility)
- `README.md` — module-level docs

## The catalog ecosystem

Going forward, BNK Forge content is splitting into **per-target catalog repos** so each deployment target (cloud or on-prem) can evolve at its own pace and Forge can register them independently.

| Repo | What it's for | Status |
|---|---|---|
| [`bnk-forge-catalog-shared`](https://github.com/JLCode-tech/bnk-forge-catalog-shared) | Upstream library — the 3 cloud-agnostic Kubernetes primitives (`bnk-prerequisites`, `cert-manager`, `bnk-cert-issuer`). Per-target catalogs vendor from it. | Live |
| [`bnk-forge-catalog-aws-eks`](https://github.com/JLCode-tech/bnk-forge-catalog-aws-eks) | AWS EKS deployment catalog. | In progress (existing-cluster blueprint partial; FLO/CNEInstance/license pending) |
| [`jgruberf5/bnk-forge-ibm-roks-cluster`](https://github.com/jgruberf5/bnk-forge-ibm-roks-cluster) | IBM ROKS deployment catalog (community-maintained). | Live |
| `bnk-forge-catalog-azure-aks` | Planned. | Not started |
| `bnk-forge-catalog-gcp-gke` | Planned. | Not started |
| `bnk-forge-catalog-onprem-k8s` | Planned. | Not started |

This repo stays as the canonical source for BNK 2.2 on existing Forge installations and is not being migrated. New deployment scenarios (and the BNK 2.3+ release branches when those land) will likely be added in the per-target catalogs first.

## Branches

| Branch | Purpose |
|---|---|
| `release/2.2` | BNK 2.2 GA content — what your Forge installation should point at for production |
| `main` | Mirrors the latest stable release branch (currently `release/2.2`) |

## Repository contract

- **Validation**: `python3 scripts/validate_pack_manifests.py` (v2alpha1 schema) and `python3 scripts/validate_module_metadata.py` (release-manifest reconciliation). Both run in CI on every PR.
- **Module metadata**: see [`MODULE_METADATA_SCHEMA.md`](./MODULE_METADATA_SCHEMA.md).
- **Dependency wiring**: see [`DEPENDENCY_GRAPH.md`](./DEPENDENCY_GRAPH.md).

## Usage

This repo is a **read-only library** synced into Forge — don't clone or modify it directly for deployments. Customers interact through the Forge UI:

1. Select modules from the catalog
2. Configure variables (via the deploy form, credential templates, project secrets)
3. Deploy

## Reference

- [F5 Lifecycle Operator (FLO)](https://clouddocs.f5.com/bigip-next-for-kubernetes/latest/bnk-f5-lifecycle-operator.html)
- [BIG-IP Next for Kubernetes CRDs](https://clouddocs.f5.com/bigip-next-for-kubernetes/latest/spk-custom-resources.html)
- [Gateway API](https://gateway-api.sigs.k8s.io/)
