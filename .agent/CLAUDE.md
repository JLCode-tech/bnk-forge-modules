# BNK-Forge Modules - Agent Instructions

## Project Overview

**Repository**: bnk-forge-modules
**Purpose**: Official Terraform/Terragrunt module library for BNK-Forge - supporting multi-cloud deployments
**Tech Stack**: Terraform, Terragrunt, Kubernetes, AWS/Azure/GCP, F5 BIG-IP Next for Kubernetes
**Status**: Active Development - Expanding to support multiple cloud platforms and deployment patterns

This is the canonical source for infrastructure, Kubernetes, and BNK deployment modules across multiple cloud platforms. Users select modules through BNK-Forge UI, which generates their customized project in `bnk-forge-live`.

### Key Technologies
- **Infrastructure as Code**: Terraform 1.5+, Terragrunt
- **Cloud Platforms**: AWS (production), Azure (planned), GCP (planned), On-Premises (planned)
- **Container Orchestration**: Kubernetes 1.28+, Amazon EKS, Azure AKS (planned), Google GKE (planned)
- **Networking**: Multus CNI, SR-IOV, DPDK for high-performance networking
- **F5 Products**: F5 Lifecycle Operator (FLO), BIG-IP Next for Kubernetes (BNK)
- **Gateway API**: Kubernetes Gateway API for traffic management

## Quick Start Steps

### Before Making Changes

1. **Read Current State**
   ```
   Read .agent/CURRENT_WORK.md to see what's in progress
   Read .agent/BACKLOG.md to understand prioritized work
   Read .agent/DECISIONS.md for architectural context
   ```

2. **Understand the Module Structure**
   - Each module has: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `module.json`, `README.md`
   - Module categories: `infra/` (infrastructure), `k8s/` (Kubernetes prereqs), `bnk/` (BNK components)
   - Dependencies flow: infrastructure → kubernetes → bnk components
   - See `DEPENDENCY_GRAPH.md` for module dependencies

3. **Check Module Metadata**
   - Review `module.json` for module metadata schema
   - See `MODULE_METADATA_SCHEMA.md` for full schema documentation

### Development Workflow

1. **Planning**
   - For new modules or significant changes, update `.agent/DECISIONS.md` first
   - Check `.agent/BACKLOG.md` for priority and related work
   - Update `.agent/CURRENT_WORK.md` when starting work

2. **Making Changes**
   - Follow patterns in `.agent/PATTERNS.md` for consistency
   - Test module changes with `terraform validate` and `terraform plan`
   - Update module `README.md` with any new variables or behavior
   - Update `module.json` if inputs/outputs/dependencies change
   - Update `DEPENDENCY_GRAPH.md` if module dependencies change

3. **Documentation** (CRITICAL)
   - **AGENTS MUST UPDATE DOCUMENTATION AS THEY WORK**
   - Update module README.md with changes
   - Update `.agent/CURRENT_WORK.md` with progress
   - Add architectural decisions to `.agent/DECISIONS.md`
   - Update `.agent/PATTERNS.md` if introducing new patterns
   - **The next agent depends on accurate documentation**

4. **Testing**
   - Run `/validate` skill to validate all modules
   - Check for Terraform formatting with `terraform fmt -check -recursive`
   - Ensure `module.json` is valid JSON

5. **Committing**
   - Follow commit conventions (see Commit Conventions section)
   - Update `.agent/CURRENT_WORK.md` before committing
   - Use `/commit` skill for guided commits

## Key Directories and Critical Files

### Module Directories
- **`infra/aws/`** - AWS infrastructure modules (VPC, EKS, security, storage, high-performance-nodes)
- **`infra/azure/`** - Azure infrastructure modules (planned)
- **`infra/gcp/`** - GCP infrastructure modules (planned)
- **`k8s/`** - Cloud-agnostic Kubernetes prerequisite modules (cert-manager, network-setup)
- **`bnk/`** - Cloud-agnostic BNK component modules (FLO, gatewayclass, gateway, routes, policies)
- **`archived/`** - Deprecated modules now managed by F5 Lifecycle Operator

### Critical Files
- **`README.md`** - Main repository documentation
- **`DEPENDENCY_GRAPH.md`** - Module dependency visualization and ordering
- **`MODULE_METADATA_SCHEMA.md`** - Schema for `module.json` files
- **`.agent/CURRENT_WORK.md`** - Active work tracking (UPDATE THIS!)
- **`.agent/DECISIONS.md`** - Architecture decision records
- **`.agent/PATTERNS.md`** - Code conventions and patterns

### Module Structure (Standard)
Each module directory contains:
```
module-name/
├── main.tf              # Primary Terraform resources
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── versions.tf          # Provider requirements
├── module.json          # BNK-Forge metadata
├── README.md            # Module documentation
├── scripts/             # Helper scripts (if needed)
├── manifests/           # Kubernetes manifests (if needed)
└── templates/           # Template files (if needed)
```

## Common Tasks and Commands

### Terraform Operations
```bash
# Validate all modules
terraform validate

# Format code
terraform fmt -recursive

# Check formatting
terraform fmt -check -recursive
```

### Module Validation
```bash
# Validate module.json files
find . -name "module.json" -exec jq empty {} \;

# Check for required files in modules
find infra k8s bnk -name "module.json" -type f
```

### Git Operations
```bash
# Check status
git status

# View changes
git diff

# View recent commits
git log --oneline -10

# Check module changes
git diff -- infra/aws/vpc/
```

### Search Operations
```bash
# Find modules by type
find infra -name "module.json"
find k8s -name "module.json"
find bnk -name "module.json"

# Search for specific patterns
grep -r "variable.*vpc_id" .
grep -r "output.*cluster_name" .
```

## Documentation Update Requirements

### CRITICAL: Keep Documentation Current

**Why This Matters**
- This repository has multiple agents working across sessions
- The next agent relies on accurate documentation to understand context
- Without updates, work gets duplicated or conflicts arise

**What to Update**

1. **During Active Work** - Update `.agent/CURRENT_WORK.md`:
   - Move task to "Active Tasks" when starting
   - Add session notes with key findings
   - Update progress and blockers

2. **When Making Decisions** - Update `.agent/DECISIONS.md`:
   - Document architectural choices
   - Explain trade-offs considered
   - Reference related modules or issues

3. **When Changing Patterns** - Update `.agent/PATTERNS.md`:
   - Add new coding patterns
   - Update conventions if they change
   - Document gotchas or lessons learned

4. **When Completing Work** - Update `.agent/CURRENT_WORK.md`:
   - Move task to "Recently Completed"
   - Add completion date and summary
   - Update handoff notes for next agent

5. **Module Documentation** - Update module files:
   - `README.md` - Usage and examples
   - `module.json` - Metadata and dependencies
   - `DEPENDENCY_GRAPH.md` - If dependencies change

**Before Ending Session**
- Review `.agent/CURRENT_WORK.md` handoff checklist
- Ensure all documentation is current
- Commit documentation updates

## Commit Conventions

Follow these conventions for commit messages:

### Format
```
<type>(<scope>): <subject>

<body>

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Types
- `feat` - New feature or module
- `fix` - Bug fix
- `docs` - Documentation only changes
- `refactor` - Code restructuring without behavior change
- `test` - Adding or updating tests
- `chore` - Maintenance tasks (dependencies, tooling)
- `perf` - Performance improvements

### Scope
- Module path: `infra/vpc`, `k8s/cert-manager`, `bnk/flo`
- Category: `infra`, `k8s`, `bnk`, `agent-docs`
- Component: `scripts`, `manifests`, `docs`

### Examples
```
feat(bnk/gateway): add support for multiple listeners

Add ability to configure multiple Gateway listeners with different
protocols and ports for advanced routing scenarios.

Co-Authored-By: Claude <noreply@anthropic.com>
```

```
fix(infra/high-performance-nodes): correct DPDK binding script

Fix issue where DPDK interfaces were not properly bound to vfio-pci
driver on node initialization.

Co-Authored-By: Claude <noreply@anthropic.com>
```

```
docs(agent-docs): update CURRENT_WORK with gateway enhancements

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Module Development Guidelines

### Creating New Modules

1. **Use Template** - Start from `templates/` directory
2. **Follow Structure** - Include all standard files
3. **Update Metadata** - Create comprehensive `module.json`
4. **Document Dependencies** - Update `DEPENDENCY_GRAPH.md`
5. **Write Tests** - Include validation examples
6. **Update Backlog** - Add related enhancement ideas

### Modifying Existing Modules

1. **Read First** - Understand current implementation
2. **Check Dependencies** - Review `DEPENDENCY_GRAPH.md`
3. **Preserve Compatibility** - Don't break existing users
4. **Update Outputs** - Keep `module.json` in sync
5. **Test Changes** - Validate with `terraform validate`
6. **Document Changes** - Update README and CURRENT_WORK

### Module Quality Standards

- **Terraform Best Practices** - Use recommended patterns
- **Variable Validation** - Add validation rules where appropriate
- **Clear Outputs** - Export all useful values
- **Comprehensive Docs** - README with examples
- **Security** - Follow AWS security best practices
- **Performance** - Consider cost and resource efficiency

## Handoff Protocol

When ending a session, complete the `.agent/CURRENT_WORK.md` handoff checklist:

- [ ] Current tasks status updated
- [ ] Session notes capture key findings
- [ ] Any blockers or questions documented
- [ ] Related decisions logged in DECISIONS.md
- [ ] New patterns added to PATTERNS.md
- [ ] Module documentation updated
- [ ] Git status is clean or changes are documented
- [ ] Next steps are clear

## Available Skills

Use these skills for common workflows:

- `/validate` - Validate all Terraform modules
- `/format` - Format all Terraform files
- `/check-modules` - Verify module structure and metadata
- `/commit` - Guided commit with conventions
- `/status` - Quick project status check
- `/sync-docs` - Update all module documentation

## Getting Help

- Read `README.md` for repository overview
- Check `DEPENDENCY_GRAPH.md` for module relationships
- Review `MODULE_METADATA_SCHEMA.md` for metadata format
- See `archived/README.md` for deprecated module info
- Ask questions about F5 products or Kubernetes patterns

## Remember

1. **Document as you work** - Don't save it for the end
2. **Update CURRENT_WORK.md** - It's your contract with the next agent
3. **Follow patterns** - Check PATTERNS.md for consistency
4. **Test changes** - Always validate before committing
5. **Think about users** - These modules are used by real projects
6. **Security matters** - This is infrastructure code
7. **Ask questions** - If unsure, check with the user

---

**Last Updated**: 2026-01-18
**Version**: 1.0.0
