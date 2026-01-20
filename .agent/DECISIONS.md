# Architecture Decision Records - BNK-Forge Modules

Last Updated: 2026-01-20

## Overview

This document captures architectural decisions made for the bnk-forge-modules repository. Use the ADR format below when documenting significant decisions.

## Active Decisions

### ADR-001: Module Metadata Schema (module.json)

**Date**: Pre-2026 (Existing)
**Status**: Accepted
**Deciders**: BNK-Forge Team

**Context**:
BNK-Forge needs structured metadata about each Terraform module to generate user projects, validate dependencies, and provide a good UI experience.

**Decision**:
Implement `module.json` files in each module directory with standardized schema including:
- Module name, version, category
- Input variables (required/optional)
- Output values
- Dependencies (required/optional)
- Cloud platform support
- Deployment metadata

**Consequences**:
- Positive: Enables automated project generation and validation
- Positive: Clear contract between modules and BNK-Forge tool
- Positive: Self-documenting modules
- Negative: Additional maintenance burden (keep in sync with Terraform)
- Negative: Schema changes require updates across all modules

**Related**: `MODULE_METADATA_SCHEMA.md`

---

### ADR-002: F5 Lifecycle Operator (FLO) as Deployment Method

**Date**: 2024 (F5 BNK v2.1.0+)
**Status**: Accepted
**Deciders**: F5 Product Team

**Context**:
Previously, BNK components (CWC, DSSM, TMM, etc.) were deployed individually via Terraform/Helm. This created complexity and maintenance burden. F5 introduced Lifecycle Operator (FLO) to automate BNK deployment.

**Decision**:
- Use FLO as the primary BNK deployment mechanism
- Archive individual component modules (cwc, dssm, f5-controller, fluentd, crds)
- Simplify to: prerequisites → FLO → BnkGatewayClass (triggers FLO auto-deployment)

**Consequences**:
- Positive: Simplified deployment workflow
- Positive: F5 manages component compatibility
- Positive: Automatic updates and lifecycle management
- Positive: Reduced module maintenance
- Negative: Less granular control over individual components
- Negative: Dependency on FLO version compatibility

**Related**: `archived/README.md`, `bnk/flo/`, `bnk/bnk-gatewayclass/`

---

### ADR-003: Three-Tier Module Organization

**Date**: Pre-2026 (Existing)
**Status**: Accepted
**Deciders**: BNK-Forge Team

**Context**:
Need clear organization for modules targeting different deployment layers and cloud platforms.

**Decision**:
Organize modules into three top-level categories:
1. `infra/` - Cloud-specific infrastructure (VPC, clusters, compute, storage)
2. `k8s/` - Cloud-agnostic Kubernetes prerequisites (cert-manager, CNI, monitoring)
3. `bnk/` - Cloud-agnostic BNK components (FLO, gateways, routes, policies)

**Consequences**:
- Positive: Clear separation of concerns
- Positive: Easy to find modules by layer
- Positive: Cloud-specific vs agnostic is obvious
- Positive: Supports multi-cloud expansion
- Negative: Some ambiguity (e.g., where does cloud-specific K8s config go?)

**Related**: `README.md` structure, `DEPENDENCY_GRAPH.md`

---

### ADR-004: High-Performance Networking Strategy

**Date**: Pre-2026 (Existing)
**Status**: Accepted
**Deciders**: BNK-Forge Team

**Context**:
BNK requires high-performance networking for traffic management. Standard Kubernetes networking is insufficient for high-throughput, low-latency requirements.

**Decision**:
Implement high-performance networking using:
- **SR-IOV**: Single Root I/O Virtualization for direct NIC access
- **DPDK**: Data Plane Development Kit for userspace packet processing
- **Multus CNI**: Multiple network interface support in pods
- **Dedicated node pools**: Separate high-performance nodes with specialized configuration

**Consequences**:
- Positive: Meets BNK performance requirements
- Positive: Industry-standard technologies
- Positive: Scalable architecture
- Negative: Complex setup and configuration
- Negative: Cloud-specific implementations required
- Negative: Requires specialized instance types
- Negative: Higher infrastructure costs

**Related**: `infra/aws/high-performance-nodes/`, `k8s/network-setup/`

---

### ADR-005: Multi-Agent Workflow Structure

**Date**: 2026-01-18
**Status**: Accepted
**Deciders**: Repository Owner

**Context**:
Repository will have multiple Claude Code agents working across sessions. Need coordination mechanism to prevent duplicate work, capture decisions, and ensure continuity.

**Decision**:
Implement multi-agent workflow structure:
- `.agent/CLAUDE.md` - Main agent instructions
- `.agent/CURRENT_WORK.md` - Active task tracking
- `.agent/BACKLOG.md` - Prioritized work queue
- `.agent/DECISIONS.md` - This file (ADR log)
- `.agent/PATTERNS.md` - Code conventions
- `.claude/skills/` - Project-specific automation
- `.claude/settings.local.json` - Bash permissions

**Consequences**:
- Positive: Effective agent coordination
- Positive: Knowledge preservation across sessions
- Positive: Clear task prioritization
- Positive: Consistent patterns and conventions
- Negative: Additional documentation maintenance
- Negative: Agents must read and update docs (discipline required)

**Related**: `.agent/` directory contents

---

### ADR-006: Module Dependency and I/O Wiring Enhancement

**Date**: 2026-01-20
**Status**: Accepted
**Deciders**: Repository Owner, Claude Code Agent

**Context**:
The `module.json` files contain rich metadata about module dependencies and input/output relationships:
- `dependencies.required[]` - which modules must be deployed first
- `inputs[].source: "module"` with `from_module` and `from_output` - how inputs should be wired
- `outputs[].used_by` - which modules consume each output
- `deployment.order` - correct ordering for deployment

However, bnk-forge was not fully utilizing this data:
- Dependencies were detected via hardcoded rules in `MODULE_DEPENDENCY_RULES`
- Input wiring from module outputs was not implemented
- root.hcl was not updated with real output values after module apply
- UI showed "No dependencies" regardless of actual deps

**Decision**:
Implement full module dependency and I/O wiring:

1. **Catalog Sync**: Parse `module.json` and store in `ModuleLibrary` table
2. **Dependency Resolution**: Use `dependencies.required[]` instead of hardcoded rules
3. **Input Wiring Service**: Track which inputs come from other modules
4. **root.hcl Updates**: After module apply, update locals with real output values
5. **UI Enhancement**: Display actual dependencies and input sources

**Consequences**:
- Positive: Accurate dependency detection from authoritative source
- Positive: Automatic output→input wiring reduces manual configuration
- Positive: Better UX with real dependency visualization
- Positive: root.hcl stays in sync with deployed state
- Negative: Requires bnk-forge code changes (Phases 1-5 in implementation plan)
- Negative: Need to ensure module.json is kept in sync with Terraform code

**Implementation Plan**: `.agent/IMPLEMENTATION_PLAN_DEPENDENCY_WIRING.md`

**Related**:
- `MODULE_METADATA_SCHEMA.md`
- `DEPENDENCY_GRAPH.md`
- `bnk-forge/backend/services/module_catalog_service.py`
- `bnk-forge/backend/services/project_service.py`

---

### ADR-007: Remove Project-Level Variables from Module Inputs

**Date**: 2026-01-20
**Status**: Accepted
**Deciders**: Repository Owner, Claude Code Agent

**Context**:
Module.json files were declaring project-level variables like `project_name`, `environment`, `aws_region`, and `common_tags` in their `inputs.required` or `inputs.optional` arrays. However, bnk-forge automatically defines these variables in the generated root.hcl file for all projects.

This created duplication issues:
- Users saw `EDIT_ME_PROJECT_NAME` placeholders even though project_name was already defined in root.hcl
- root.hcl contained redundant variable declarations
- Confusion about what users actually needed to configure
- Module inputs polluted with non-module-specific variables

**Decision**:
Remove all project-level variables from module.json `inputs` sections:
- **Remove**: `project_name`, `environment`, `aws_region`, `aws_profile` (infrastructure config)
- **Remove**: `common_tags`, `common_labels` (project-wide tagging)
- **Keep**: Module-specific user inputs (e.g., `vpc_cidr`, `user_ip`, `license_mode`)
- **Keep**: Module dependency inputs with `source: "module"` (e.g., `vpc_id` from infra/aws/vpc)

Note: Terraform `variables.tf` files still declare these variables. They inherit values from root.hcl via Terragrunt.

**Consequences**:
- Positive: root.hcl only shows variables users actually need to configure
- Positive: Clear separation between project config and module config
- Positive: No more duplicate/redundant variable declarations
- Positive: Cleaner module.json files (149 lines removed across 13 modules)
- Positive: Better UX in bnk-forge UI (no misleading placeholders)
- Negative: Need to maintain discipline when creating new modules (don't add project-level vars)
- Negative: Need to update bnk-forge documentation to reflect this convention

**Modules Updated**:
- infra/aws/vpc, security, eks, high-performance-nodes (removed project_name, environment, common_tags)
- k8s/cert-manager, network-setup (removed common_labels)
- bnk/far-setup, flo, bnk-gatewayclass, gateway, routes, bnk-secpolicy, bnk-netpolicy (removed common_labels)

**Related**:
- ADR-006 (Module Dependency Wiring) - supports cleaner input definitions
- `MODULE_METADATA_SCHEMA.md` - should document this convention
- All module.json files

---

## Pending Decisions

### Azure Architecture Patterns

**Status**: Research Needed
**Target Date**: TBD

**Question**:
What architecture patterns should we use for Azure infrastructure modules?

**Options**:
1. Mirror AWS architecture exactly (VNet = VPC, AKS = EKS, etc.)
2. Use Azure-native patterns (Hub-Spoke VNet topology, etc.)
3. Hybrid approach (match AWS where possible, use Azure best practices where different)

**Considerations**:
- User familiarity and learning curve
- Azure best practices
- Cost implications
- Performance characteristics
- Module reusability

**Next Steps**:
- Research Azure networking best practices
- Review Azure AKS high-performance networking options
- Prototype initial modules
- Get user feedback

---

### GCP Architecture Patterns

**Status**: Research Needed
**Target Date**: TBD

**Question**:
What architecture patterns should we use for GCP infrastructure modules?

**Options**:
1. Mirror AWS architecture
2. Use GCP-native patterns (VPC-native clusters, Shared VPC, etc.)
3. Hybrid approach

**Considerations**:
- GCP networking model differences
- GKE specifics vs EKS/AKS
- gVNIC for high-performance networking
- Cost and performance

**Next Steps**:
- Research GCP networking and GKE best practices
- Evaluate gVNIC performance for BNK workloads
- Prototype initial modules

---

### Module Versioning Strategy

**Status**: Discussion Needed
**Target Date**: TBD

**Question**:
How should we version modules and handle breaking changes?

**Options**:
1. Semantic versioning in module.json (current)
2. Git tags for module versions
3. Separate branches for major versions
4. Combination approach

**Considerations**:
- BNK-Forge integration (how does tool handle versions?)
- User migration path for breaking changes
- Maintenance burden of multiple versions
- Terraform module best practices

**Next Steps**:
- Review how BNK-Forge currently uses module versions
- Define versioning policy
- Document upgrade procedures

---

## ADR Template

Use this template when documenting new decisions:

```markdown
### ADR-XXX: Decision Title

**Date**: YYYY-MM-DD
**Status**: Proposed | Accepted | Deprecated | Superseded
**Deciders**: Who made this decision

**Context**:
What is the issue we're trying to solve? What are the constraints?

**Decision**:
What did we decide to do and why?

**Consequences**:
What are the positive and negative outcomes of this decision?
- Positive: ...
- Negative: ...

**Alternatives Considered**:
(Optional) What other options did we consider?

**Related**: Links to files, modules, or other ADRs
```

---

## Notes

- Keep decisions focused and concise
- Update status as decisions evolve
- Link to relevant code, modules, or documentation
- Capture the "why" not just the "what"
- Include alternatives considered to help future decision-makers
- Move outdated decisions to a "Superseded" section rather than deleting
