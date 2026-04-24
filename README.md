# BNK-Forge Module Library

Curated OpenTofu / Terraform modules for deploying [F5 BIG-IP Next for Kubernetes (BNK)](https://clouddocs.f5.com/bigip-next-for-kubernetes/) — infrastructure, Kubernetes prerequisites, BNK platform components, and demo applications.

> ## ⚠️ This branch (`main`) is intentionally empty
>
> `main` is a **landing page** — it points to the active release branches. **All real module code lives on `release/X.Y` branches.**
>
> Pick the release branch that matches the F5 BNK version you want to deploy.

---

## Active release branches

| Branch | F5 BNK version | Status | Use this if you... |
|---|---|---|---|
| **[`release/2.2`](https://github.com/JLCode-tech/bnk-forge-modules/tree/release/2.2)** | BNK 2.2 GA | **Active — current stable** | Are deploying BNK today |
| `release/2.3` | BNK 2.3 (when GA) | Not yet open | Want the next release |

History of past releases lives in their respective `release/X.Y` branches (never deleted).

---

## Quick start

Clone the **release branch** that matches your target BNK version, not `main`:

```bash
# Latest stable
git clone -b release/2.2 https://github.com/JLCode-tech/bnk-forge-modules.git

cd bnk-forge-modules
cat VERSION   # see the rev you're at (e.g. 2.2-rev.27)
```

Once cloned, see the release branch's own `README.md` and `DEPENDENCY_GRAPH.md` for the module catalog and deployment order.

---

## Repository conventions

### Branch model

- **`main`** — this landing page only. No code. Auto-tracks the latest stable `release/X.Y` for documentation purposes.
- **`release/X.Y`** — protected, PR-only. One per BNK release. Receives bug fixes and minor enhancements that maintain compatibility with that BNK version.
- **`feature/X.Y-foo`** — topic branches. Open against the targeted `release/X.Y`; deleted after merge.

### Cross-release fixes

A fix that applies to multiple BNK versions is cherry-picked from one `release/X.Y` to another via PR. Never direct-pushed.

### Branch protection

Both `main` and `release/*` branches are protected:
- PR required (no direct push)
- Squash or rebase merge only (linear history)
- No force-pushes, no branch deletion
- All conversations resolved before merge

CI status checks will be added as the validation harness comes online.

---

## What's where on a release branch

Each `release/X.Y` branch contains the full module catalog:

```
infra/                      Cloud-specific infrastructure modules
  ├── aws/                  EKS, VPC, security, high-performance nodes, IRSA, ...
  ├── gcp/                  (release/2.3+)
  ├── azure/                (release/2.3+)
  ├── ocp/                  OpenShift on-prem
  ├── ubuntu/               Bare-metal Ubuntu
  └── k8s/                  Generic K8s helpers

k8s/                        Cloud-AGNOSTIC Kubernetes plumbing
  ├── bnk-prerequisites/    Namespaces (f5-bnk, f5-utils)
  ├── cert-manager/         Helm install
  ├── network-setup/        NetworkAttachmentDefinitions for TMM
  └── ...

bnk/                        Cloud-AGNOSTIC BNK platform CRs
  ├── flo/                  F5 Lifecycle Operator
  ├── cneinstance/          CNEInstance CR (FLO deploys TMM, CNE controller, etc.)
  ├── bnk-vlans/            F5SPKVlan CRs
  ├── gateway/              Gateway API resources
  └── ...

app/                        Demo + reference applications
  ├── demo-*                Cloud-agnostic demo apps
  └── bedrock-smartllm-*    AWS-specific (Bedrock) — declared via module.json
```

### Architecture rules

- **`infra/{cloud}/`** is cloud-specific by design.
- **`k8s/`** and **`bnk/`** must be cloud-agnostic — no `aws`/`google`/`azurerm` providers in their `versions.tf`.
- **`app/`** may be cloud-coupled but must declare it via `module.json` (`cloud_specific`, `supported_platforms`).

A CI gate enforces these rules on every PR.

---

## Reference docs

On each release branch:

- **`README.md`** — module catalog, version compatibility matrix, deployment overview
- **`DEPENDENCY_GRAPH.md`** — module dependency map and deployment order
- **`MODULE_METADATA_SCHEMA.md`** — `module.json` contract for cataloging
- **`VERSION`** — the release branch's revision (e.g. `2.2-rev.27`)
- **`docs/plans/`** — multi-step refactor planning docs (when active work is in flight)
- **Per-module `README.md`** + `CHANGELOG.md` + `bnkforge.pack.json` + `module.json`

---

## Related

- **F5 BIG-IP Next for Kubernetes** — official docs: <https://clouddocs.f5.com/bigip-next-for-kubernetes/>
- **`bnk-forge-v2`** (private) — the BNK-Forge control plane app that consumes this module library to render and apply Terraform stacks
- **F5 BNK Multi-AZ Network Architecture Deployment Guide** (Doc 3) — primary reference for AWS kernel-mode TMM deployments

---

## Contributing

1. Open an issue describing the change against a target `release/X.Y` branch
2. Branch as `feature/X.Y-<short-name>` from `release/X.Y`
3. Open PR back to that `release/X.Y`
4. PR must squash-merge or rebase-merge (no merge commits)
5. Bump `VERSION` (`X.Y-rev.N` → `X.Y-rev.N+1`) in the same PR

For cross-release backports / forwardports: cherry-pick the merge commit and open a separate PR per target branch.

---

*This README is the only file maintained on `main`. To work with modules, switch to a `release/X.Y` branch.*
