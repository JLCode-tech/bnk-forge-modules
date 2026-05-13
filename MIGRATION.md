# BNK-Forge Module Repo — Migration to Per-Cloud Architecture

This document captures the architectural direction for the BNK-Forge module ecosystem and the role this repository will play once the migration is complete.

## Target architecture

The BNK-Forge module ecosystem is moving to a **per-target-platform repo** pattern, modelled on [`jgruberf5/bnk-forge-ibm-roks-cluster`](https://github.com/jgruberf5/bnk-forge-ibm-roks-cluster). Each target platform gets its own repo with:

- **`modules/`** — single-purpose Terraform modules, one per deployment step (cluster create, install cert-manager, install FLO, deploy CNEInstance, apply license, etc.). Cloud-specific concerns (IAM, registry auth, networking) live here.
- **`blueprints/`** — hand-authored `forge-blueprint.json` manifests that chain those modules together end-to-end.
- The repo registers in Forge as both a Module Source and a Blueprint Source.

```
bnk-forge-modules                  <-- THIS REPO: shared cloud-agnostic k8s layer
├── k8s/bnk-prerequisites/         (namespaces + FAR secrets + manifest)
├── k8s/cert-manager/              (Jetstack Helm install)
└── k8s/bnk-cert-issuer/           (BNK Issuer/ClusterIssuer CRs)

bnk-forge-ibm-roks-cluster         <-- EXISTS (jgruberf5)
bnk-forge-aws-eks-cluster          <-- PLANNED
bnk-forge-azure-aks-cluster        <-- PLANNED
bnk-forge-gcp-gke-cluster          <-- PLANNED
bnk-forge-onprem-k8s               <-- PLANNED (any on-prem Kubernetes)
```

## What this repository becomes

After the migration, `bnk-forge-modules` is **the shared cloud-agnostic Kubernetes layer**. It hosts only modules that:

- Touch the Kubernetes API exclusively (no cloud-provider APIs).
- Use no cloud-specific authentication (no IAM trusted profiles, no IRSA, no GCP service account keys).
- Have the same behavior on EKS, AKS, GKE, ROKS, vanilla on-prem, and kind.

Every per-cloud and on-prem repo will reference modules from here for their shared prerequisites, rather than vendoring copies.

### What stays here

| Module | Purpose |
|---|---|
| `k8s/bnk-prerequisites` | Namespaces, FAR pull secrets, BNK manifest download + version discovery. Foundation module — every downstream module depends on it. |
| `k8s/cert-manager` | Deploys Jetstack cert-manager with BNK-compatible defaults. |
| `k8s/bnk-cert-issuer` | Creates BNK-managed self-signed CA + ClusterIssuer CRs for FLO certificate flows. |

### What moves out

| Module | Where it goes | Why |
|---|---|---|
| `bnk/flo` | Vendored per-cloud (each per-cloud repo gets its own copy) | Install model differs by cloud: IBM IAM trusted profile, AWS IRSA, Azure workload identity. BIG-IP CIS controller wiring is cloud-specific. |
| `bnk/cneinstance` | Vendored per-cloud | Chassis configuration tracks the underlying NIC stack (AWS ENA vs IBM SR-IOV vs Azure Accelerated Networking). PR #58 added AWS-specific `F5BnkGateway` chassis logic — exactly the kind of cloud-specific divergence that vendoring contains. |
| `k8s/network-setup` | Vendored per-cloud | Multus + NAD configuration depends on cloud-specific NIC drivers and SR-IOV/DPDK knobs. |

### What retires

| Module | Replacement | When |
|---|---|---|
| `k8s/bnk-namespaces` | `k8s/bnk-prerequisites` (superset) | Phase 4 — only `bnk/far-setup` still references it, and that retires too. |
| `bnk/far-setup` | `k8s/bnk-prerequisites` (already absorbs FAR secret setup) | Phase 4 — catalog `reason` field already names bnk-prerequisites as the replacement. |
| `bnk/bnk-gateway-ext` | None | Phase 4 — no consumers anywhere in the repo or templates. |
| `bnk/bnk-vlans`, `bnk/gateway`, `bnk/routes`, `bnk/bnk-netpolicy`, `bnk/bnk-secpolicy`, `bnk/bnk-gatewayclass` | TBD per-module | Phase 4 decision: some may move to per-cloud repos, some may stay shared, some may retire. Driven by whether the underlying CR apply is cloud-specific. |

## Phased plan

| Phase | Scope | Status |
|---|---|---|
| 0 | Land in-flight PRs (manifest `version` fix, AWS/EKS chassis, namespace alignment) | Done |
| 1 + 2 | Create missing `bnkforge.pack.json` for `k8s/bnk-prerequisites`; add `k8s/bnk-cert-issuer` to the catalog; document the migration direction (this file) | In progress |
| 3 | Create per-cloud repos: `bnk-forge-aws-eks-cluster`, then Azure, GCP, on-prem. Vendor FLO + CNEInstance + network-setup into each. Hand-author per-cloud blueprints. | Not started |
| 4 | Retire deprecated/legacy modules from this repo once per-cloud repos cover the moved-out modules. Per-module decision for ambiguous legacies. | Not started |
| 5 | Drop the `catalog/release-*.json` auto-generated transition blueprint path entirely; this repo serves only its shared modules. | Not started |

## Versioning contract

This repo (and every per-cloud repo) follows the **BNK release cadence**. Current BNK GA is **2.3**. Branches and tags should track BNK release boundaries:

- `release/2.2` — current branch
- `release/2.3` — when BNK 2.3 content lands
- `release/2.4`, `release/3.x` — as BNK ships them

The pack JSON schema (`bnkforge.pack.json`) and blueprint manifest schema (`forge-blueprint.json`) are the **stable API** between module repos and Forge. BNK version bumps ship as content changes here, never as Forge code changes. Forge must never branch on a BNK version string.

## Reference

- IBM repo (gold-standard pattern): https://github.com/jgruberf5/bnk-forge-ibm-roks-cluster
- Forge app: `bnk-forge-v2`

---

*Last updated: 2026-05-13*
