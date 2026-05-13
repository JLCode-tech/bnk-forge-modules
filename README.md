# bnk-forge-modules

Original BNK Forge module library — the repo that existing Forge installations point at for BNK 2.2 GA. Curated OpenTofu / Terraform modules for AWS infrastructure, Kubernetes prerequisites, BNK platform components, and demo applications.

> `main` is a **landing page**. All module code lives on the `release/X.Y` branches. Pick the branch matching the BNK version you want to deploy.

## Where this fits in the catalog ecosystem

Going forward, BNK Forge content is splitting across **per-target catalog repos** so each deployment target evolves independently. This repo continues to host the BNK 2.2 GA reference content unchanged — existing Forge installations consume it without disruption.

| Repo | What it's for | Status |
|---|---|---|
| **`bnk-forge-modules`** (this repo) | Original Forge module library — BNK 2.2 GA reference content. Existing Forge installations point here via `module_library.git_url`. | Live |
| [`bnk-forge-catalog-shared`](https://github.com/JLCode-tech/bnk-forge-catalog-shared) | Upstream library — the 3 cloud-agnostic k8s primitives. Per-target catalogs vendor from it. | Live |
| [`bnk-forge-catalog-aws-eks`](https://github.com/JLCode-tech/bnk-forge-catalog-aws-eks) | AWS EKS deployment catalog. | Partial (register + prereqs + cert-manager + cert-issuer; FLO + CNEInstance + License pending) |
| [`jgruberf5/bnk-forge-ibm-roks-cluster`](https://github.com/jgruberf5/bnk-forge-ibm-roks-cluster) | IBM ROKS catalog (community-maintained). | Live |
| `bnk-forge-catalog-azure-aks` | Planned. | Not started |
| `bnk-forge-catalog-gcp-gke` | Planned. | Not started |
| `bnk-forge-catalog-onprem-k8s` | Planned. | Not started |

If you're starting a new Forge installation today, you may want to point at one of the per-target catalogs in addition to (or instead of) this repo. If you already have Forge pointing here, no migration is needed for BNK 2.2.

## Release branches

| Branch | F5 BNK version | Status |
|---|---|---|
| [`release/2.2`](https://github.com/JLCode-tech/bnk-forge-modules/tree/release/2.2) | BNK 2.2 GA | Active — current stable |
| `release/2.3` | BNK 2.3 (when GA) | Not yet open |

Past releases stay on their `release/X.Y` branches indefinitely.

## What's on a release branch

`release/2.2` contains the full BNK deployment stack:

| Family | What it covers |
|---|---|
| `infra/aws/` | VPC, EKS, security/IAM, storage, high-performance nodes (SR-IOV + DPDK + Multus) |
| `k8s/` | `bnk-prerequisites`, `cert-manager`, `network-setup`, `bnk-cert-issuer` |
| `bnk/` | `flo`, `cneinstance`, `bnk-vlans`, `bnk-gatewayclass`, `gateway`, `routes`, policies |
| `app/` | Reference demo stack including a GenAI Bedrock proxy + analyzer |

Full module inventory, dependency graph, and deployment order are on the [release/2.2 README](https://github.com/JLCode-tech/bnk-forge-modules/blob/release/2.2/README.md).

## Configure Forge to use this library

In Forge → **Settings → Defaults**:

```
Module Library Git URL: https://github.com/JLCode-tech/bnk-forge-modules.git
Module Library Git Ref: release/2.2
```

Then sync at **Settings → Environment Config → Sync Modules**.

## Quick start (for direct git use, e.g. CI inspection)

```bash
git clone -b release/2.2 https://github.com/JLCode-tech/bnk-forge-modules.git
cd bnk-forge-modules
cat VERSION   # current rev, e.g. 2.2-rev.33
```

`main` itself holds only this landing page — clone a release branch for the catalog.

## Branch protection

Both `main` and `release/*` branches are PR-only. Squash or rebase merge for linear history. No force-pushes, no branch deletion.

## Contributing

1. Open an issue describing the change against a target `release/X.Y` branch
2. Branch as `feature/X.Y-<short-name>` from `release/X.Y`
3. Open PR back to that `release/X.Y` — squash or rebase merge
4. Bump `VERSION` (`X.Y-rev.N` → `X.Y-rev.N+1`) in the same PR

Cross-release fixes: cherry-pick the merge commit, separate PR per target branch.

## Reference

- [F5 BIG-IP Next for Kubernetes](https://clouddocs.f5.com/bigip-next-for-kubernetes/)
- [BNK Forge Catalog Repo Contract](https://github.com/JLCode-tech/bnk-forge-catalog-shared/blob/release/2.2/CATALOG_REPO_CONTRACT.md) — applies to the `bnk-forge-catalog-*` ecosystem
- `bnk-forge-v2` — the Forge control plane app that consumes this library
