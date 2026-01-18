# BNK-Forge Modules - Quick Reference

This is the official Terraform/Terragrunt module library for BNK-Forge, supporting multi-cloud BIG-IP Next for Kubernetes deployments.

## For Claude Code Agents

**IMPORTANT**: Read `.agent/CLAUDE.md` for complete instructions.

## Quick Start

### 1. Read Current State
```
Read .agent/CURRENT_WORK.md - See active tasks
Read .agent/BACKLOG.md - Check prioritized work
Read .agent/DECISIONS.md - Understand architectural decisions
```

### 2. Before Making Changes
- Understand the module structure (see below)
- Review existing patterns in `.agent/PATTERNS.md`
- Check dependencies in `DEPENDENCY_GRAPH.md`
- Test with `terraform validate`

### 3. CRITICAL: Update Documentation As You Work
- **Update `.agent/CURRENT_WORK.md`** with your progress
- Add decisions to `.agent/DECISIONS.md`
- Add new patterns to `.agent/PATTERNS.md`
- Update module README.md files
- Keep `module.json` in sync with code changes

**The next agent depends on accurate documentation!**

## Project Structure

```
bnk-forge-modules/
├── .agent/                   # AGENT COORDINATION (READ FIRST)
│   ├── CLAUDE.md            # Full agent instructions
│   ├── CURRENT_WORK.md      # Active task tracking
│   ├── BACKLOG.md           # Prioritized work queue
│   ├── DECISIONS.md         # Architecture decisions
│   └── PATTERNS.md          # Code conventions
├── .claude/                  # Claude Code configuration
│   ├── skills/              # Project-specific skills
│   └── settings.local.json  # Bash permissions
├── infra/                   # Cloud-specific infrastructure
│   ├── aws/                 # AWS modules (production)
│   ├── azure/               # Azure modules (planned)
│   └── gcp/                 # GCP modules (planned)
├── k8s/                     # Cloud-agnostic K8s prerequisites
│   ├── cert-manager/
│   └── network-setup/
├── bnk/                     # Cloud-agnostic BNK components
│   ├── flo/                 # F5 Lifecycle Operator
│   ├── bnk-gatewayclass/
│   ├── gateway/
│   ├── routes/
│   ├── bnk-netpolicy/
│   └── bnk-secpolicy/
├── archived/                # Deprecated modules
├── templates/               # Module templates
├── DEPENDENCY_GRAPH.md      # Module dependencies
├── MODULE_METADATA_SCHEMA.md# module.json schema
└── README.md                # Main documentation
```

## Module Categories

- **infra/** - Cloud infrastructure (VPC, clusters, storage, high-performance nodes)
- **k8s/** - Kubernetes prerequisites (cert-manager, network setup)
- **bnk/** - BIG-IP Next for Kubernetes components

## Standard Module Files

Each module MUST have:
```
module-name/
├── main.tf              # Resources
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── versions.tf          # Provider versions
├── module.json          # BNK-Forge metadata
└── README.md            # Documentation
```

## Common Tasks

### Validate Modules
```bash
terraform fmt -check -recursive
terraform validate
find . -name "module.json" -exec jq empty {} \;
```

### Check Status
```bash
git status
git diff
```

### Use Skills
```bash
/validate    # Validate all modules
/format      # Format Terraform files
/commit      # Guided commit
/status      # Quick project check
```

## Tech Stack

- **IaC**: Terraform 1.5+, Terragrunt
- **Cloud**: AWS (production), Azure (planned), GCP (planned)
- **Kubernetes**: 1.28+, EKS/AKS/GKE
- **Networking**: Multus CNI, SR-IOV, DPDK
- **F5**: Lifecycle Operator (FLO), BIG-IP Next for Kubernetes

## Commit Conventions

Format: `<type>(<scope>): <subject>`

Types: feat, fix, docs, refactor, test, chore, perf

Examples:
```
feat(bnk/gateway): add multi-listener support
fix(infra/vpc): correct subnet tagging
docs(agent-docs): update CURRENT_WORK
```

Always include:
```
Co-Authored-By: Claude <noreply@anthropic.com>
```

## Available Skills

- `/validate` - Validate all Terraform modules
- `/format` - Format all Terraform files
- `/check-modules` - Verify module structure
- `/commit` - Guided commit with conventions
- `/status` - Quick project status

## Key Principles

1. **Document as you work** - Update `.agent/CURRENT_WORK.md` continuously
2. **Follow patterns** - Check `.agent/PATTERNS.md` for consistency
3. **Test changes** - Always validate before committing
4. **Security matters** - No hardcoded secrets, secure defaults
5. **Think multi-cloud** - Design for AWS, Azure, GCP compatibility
6. **Module quality** - This is a product, users depend on these modules

## IMPORTANT: Documentation Update Protocol

Before ending your session:
- [ ] Update `.agent/CURRENT_WORK.md` with progress
- [ ] Add any decisions to `.agent/DECISIONS.md`
- [ ] Update `.agent/PATTERNS.md` with new patterns
- [ ] Update module README.md and module.json if changed
- [ ] Ensure git status is clean or changes documented
- [ ] Next steps are clearly documented

## For New Agents

**Start here**:
1. Read `.agent/CLAUDE.md` (full instructions)
2. Read `.agent/CURRENT_WORK.md` (what's happening now)
3. Read `.agent/BACKLOG.md` (what needs to be done)
4. Read `.agent/PATTERNS.md` (how to write code)
5. Read `.agent/DECISIONS.md` (why things are the way they are)

**Then**:
- Check user's request against backlog
- Update CURRENT_WORK.md with your task
- Make changes following PATTERNS.md
- Document decisions in DECISIONS.md
- Update CURRENT_WORK.md before finishing

## Repository Type

This is a **read-only reference library** synced into BNK-Forge tool. Users select modules through BNK-Forge UI, which generates their project in `bnk-forge-live`. Direct cloning is not the intended workflow.

## Related Repositories

- **bnk-forge** - Main BNK-Forge application
- **bnk-forge-live** - User deployment projects (generated)

## Documentation

- [F5 Lifecycle Operator](https://clouddocs.f5.com/bigip-next-for-kubernetes/latest/bnk-f5-lifecycle-operator.html)
- [BNK CRDs](https://clouddocs.f5.com/bigip-next-for-kubernetes/latest/spk-custom-resources.html)
- [Gateway API](https://gateway-api.sigs.k8s.io/)

---

**Status**: Active Development - Multi-cloud expansion in progress

**Last Updated**: 2026-01-18

**Next Agent**: Read `.agent/CURRENT_WORK.md` to see what's happening now.
