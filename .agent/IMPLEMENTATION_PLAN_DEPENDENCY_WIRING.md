# Implementation Plan: Module Dependency and I/O Wiring

**Created**: 2026-01-20
**Status**: Planning
**Priority**: P0 - Critical
**Affects**: bnk-forge (primary), bnk-forge-modules (data source)

## Executive Summary

The `module.json` files in bnk-forge-modules contain rich dependency and input/output mapping data that bnk-forge is not fully utilizing. This document outlines the implementation plan to properly wire module dependencies and enable automatic output→input data flow between modules.

## Current State Analysis

### What bnk-forge-modules Provides (module.json)

```json
{
  "dependencies": {
    "required": [
      { "module": "infra/aws/vpc", "reason": "Requires VPC and subnets" }
    ]
  },
  "inputs": {
    "required": [
      {
        "name": "vpc_id",
        "source": "module",
        "from_module": "infra/aws/vpc",
        "from_output": "vpc_id"
      }
    ]
  },
  "outputs": {
    "key_outputs": [
      { "name": "cluster_name", "used_by": ["k8s/cert-manager", "bnk/far-setup"] }
    ]
  },
  "deployment": {
    "order": 3
  }
}
```

### What bnk-forge Currently Does

| Feature | Current Implementation | Gap |
|---------|----------------------|-----|
| Dependencies | Hardcoded `MODULE_DEPENDENCY_RULES` dict | Not reading module.json |
| Input wiring | Collects from variables.tf only | Ignores `source: module` inputs |
| Output capture | Parses tfstate | Not updating root.hcl |
| Deployment order | Heuristic-based | Not using `deployment.order` |
| UI display | Hardcoded "No dependencies" | Not showing real deps |

## Implementation Phases

---

## Phase 1: Module Catalog Sync Enhancement

**Location**: `bnk-forge/backend/services/module_catalog_service.py`
**Effort**: Medium
**Risk**: Low

### 1.1 Parse module.json During Sync

Update `parse_module_definition()` to read module.json:

```python
def parse_module_definition(module_dir, module_name, module_path, category):
    module_def = { ... }  # existing code

    # NEW: Read module.json if it exists
    module_json_path = os.path.join(module_dir, "module.json")
    if os.path.exists(module_json_path):
        with open(module_json_path, 'r') as f:
            module_metadata = json.load(f)

        # Extract dependencies
        deps = module_metadata.get("dependencies", {})
        module_def["dependencies_metadata"] = {
            "required": deps.get("required", []),
            "optional": deps.get("optional", [])
        }

        # Extract inputs with source mapping
        inputs = module_metadata.get("inputs", {})
        module_def["inputs_metadata"] = {
            "required": inputs.get("required", []),
            "optional": inputs.get("optional", [])
        }

        # Extract outputs
        outputs = module_metadata.get("outputs", {})
        module_def["outputs_metadata"] = outputs.get("key_outputs", [])

        # Extract deployment order
        deployment = module_metadata.get("deployment", {})
        module_def["deployment_order"] = deployment.get("order", 999)

        # Update description from module.json if better
        module_info = module_metadata.get("module", {})
        if module_info.get("description"):
            module_def["description"] = module_info["description"]

    return module_def
```

### 1.2 Update ModuleLibrary Model

**Location**: `bnk-forge/backend/models.py`

Add new columns to store rich metadata:

```python
class ModuleLibrary(Base):
    # ... existing columns ...

    # NEW columns
    dependencies_metadata = Column(JSON)  # { required: [...], optional: [...] }
    inputs_metadata = Column(JSON)        # { required: [...], optional: [...] }
    outputs_metadata = Column(JSON)       # [ { name, type, used_by, ... } ]
    deployment_order = Column(Integer, default=999)
```

### 1.3 Migration Script

```python
# migrations/add_module_metadata_columns.py
def upgrade():
    op.add_column('module_library', sa.Column('dependencies_metadata', sa.JSON))
    op.add_column('module_library', sa.Column('inputs_metadata', sa.JSON))
    op.add_column('module_library', sa.Column('outputs_metadata', sa.JSON))
    op.add_column('module_library', sa.Column('deployment_order', sa.Integer, default=999))
```

---

## Phase 2: Dependency Resolution Enhancement

**Location**: `bnk-forge/backend/services/project_service.py`, `project_modules.py`
**Effort**: Medium
**Risk**: Medium

### 2.1 Replace Hardcoded Rules with module.json Data

Delete or deprecate `MODULE_DEPENDENCY_RULES` and update `detect_module_dependencies()`:

```python
def detect_module_dependencies(library_module, existing_modules, db):
    """
    Detect dependencies using module.json metadata instead of hardcoded rules.

    Args:
        library_module: ModuleLibrary object with dependencies_metadata
        existing_modules: List of ProjectModule objects in the project
        db: Database session

    Returns:
        list: List of ProjectModule IDs this module depends on
    """
    dependencies = []

    if not library_module.dependencies_metadata:
        return []

    required_deps = library_module.dependencies_metadata.get("required", [])

    # Build lookup: module_path -> ProjectModule.id
    existing_by_path = {}
    for pm in existing_modules:
        if pm.library_module:
            existing_by_path[pm.library_module.path] = pm.id

    for dep in required_deps:
        dep_module_path = dep.get("module")  # e.g., "infra/aws/vpc"

        if dep_module_path in existing_by_path:
            dependencies.append(existing_by_path[dep_module_path])
            logger.info(f"Resolved dependency: {dep_module_path} -> ProjectModule {existing_by_path[dep_module_path]}")
        else:
            logger.warning(f"Required dependency {dep_module_path} not in project")

    return dependencies
```

### 2.2 Auto-Add Required Dependencies

When user adds a module, automatically add its required dependencies:

```python
@router.post("/project/{project_id}/add")
def add_module_to_project(project_id, request, db):
    # ... existing validation ...

    # NEW: Check and auto-add required dependencies
    if library_module.dependencies_metadata:
        required_deps = library_module.dependencies_metadata.get("required", [])
        missing_deps = []

        for dep in required_deps:
            dep_path = dep.get("module")
            # Check if dep is already in project
            exists = db.query(ProjectModule).join(ModuleLibrary).filter(
                ProjectModule.project_id == project_id,
                ModuleLibrary.path == dep_path
            ).first()

            if not exists:
                missing_deps.append({
                    "path": dep_path,
                    "reason": dep.get("reason", "Required dependency")
                })

        if missing_deps:
            # Option A: Auto-add them
            # Option B: Return error asking user to add them first
            # Recommend Option B for user control
            return {
                "error": "missing_dependencies",
                "message": "This module requires dependencies that are not in the project",
                "missing": missing_deps,
                "suggestion": "Add these modules first, or click 'Add with Dependencies' to add them all"
            }
```

### 2.3 Use Deployment Order from module.json

```python
def calculate_module_deployment_order(project_id, db):
    """Use deployment.order from module.json instead of topological sort heuristics."""
    modules = db.query(ProjectModule).filter(
        ProjectModule.project_id == project_id
    ).all()

    for module in modules:
        if module.library_module and module.library_module.deployment_order:
            module.deployment_order = module.library_module.deployment_order
        else:
            module.deployment_order = 999  # Unknown modules last

    db.commit()
```

---

## Phase 3: Input/Output Wiring

**Location**: `bnk-forge/backend/services/` (new service)
**Effort**: High
**Risk**: Medium

### 3.1 Create Input Wiring Service

```python
# services/input_wiring_service.py

class InputWiringService:
    """
    Manages the wiring of module outputs to dependent module inputs.
    """

    def __init__(self, db: Session):
        self.db = db

    def get_module_input_sources(self, library_module) -> dict:
        """
        Analyze a module's inputs and categorize by source.

        Returns:
            {
                "user": [{"name": "vpc_cidr", ...}],
                "module": [{"name": "vpc_id", "from_module": "infra/aws/vpc", "from_output": "vpc_id"}],
                "auto": [...]
            }
        """
        inputs_metadata = library_module.inputs_metadata or {}
        all_inputs = inputs_metadata.get("required", []) + inputs_metadata.get("optional", [])

        categorized = {"user": [], "module": [], "auto": []}
        for inp in all_inputs:
            source = inp.get("source", "user")
            categorized[source].append(inp)

        return categorized

    def get_pending_inputs(self, project_module) -> list:
        """
        Get list of inputs that are waiting for outputs from other modules.

        Returns list of:
            {"name": "vpc_id", "from_module": "infra/aws/vpc", "from_output": "vpc_id", "status": "pending|ready"}
        """
        if not project_module.library_module:
            return []

        input_sources = self.get_module_input_sources(project_module.library_module)
        module_inputs = input_sources.get("module", [])

        pending = []
        for inp in module_inputs:
            from_module_path = inp.get("from_module")
            from_output = inp.get("from_output")

            # Find the source module in this project
            source_pm = self.db.query(ProjectModule).join(ModuleLibrary).filter(
                ProjectModule.project_id == project_module.project_id,
                ModuleLibrary.path == from_module_path
            ).first()

            status = "missing"  # Source module not in project
            value = None

            if source_pm:
                if source_pm.status == "applied" and source_pm.outputs:
                    # Check if output exists
                    if from_output in source_pm.outputs:
                        status = "ready"
                        value = source_pm.outputs[from_output]
                    else:
                        status = "output_missing"
                else:
                    status = "pending"  # Module not yet applied

            pending.append({
                "name": inp.get("name"),
                "from_module": from_module_path,
                "from_output": from_output,
                "status": status,
                "value": value
            })

        return pending

    def are_all_inputs_ready(self, project_module) -> tuple[bool, list]:
        """Check if all module inputs from other modules are satisfied."""
        pending = self.get_pending_inputs(project_module)
        not_ready = [p for p in pending if p["status"] != "ready"]
        return len(not_ready) == 0, not_ready
```

### 3.2 Update root.hcl After Module Apply

```python
# services/root_hcl_service.py

class RootHclService:
    """Manages root.hcl generation and updates."""

    def update_with_module_outputs(self, project, applied_module, outputs: dict):
        """
        Update root.hcl locals with real output values after a module is applied.

        Args:
            project: Project object
            applied_module: ProjectModule that was just applied
            outputs: Dict of output name -> value from terraform state
        """
        root_hcl_path = os.path.join(
            project.clone_path, "projects", project.name, "root.hcl"
        )

        if not os.path.exists(root_hcl_path):
            logger.error(f"root.hcl not found at {root_hcl_path}")
            return

        # Read current root.hcl
        with open(root_hcl_path, 'r') as f:
            content = f.read()

        # Get outputs metadata to know which outputs should be exposed
        if applied_module.library_module and applied_module.library_module.outputs_metadata:
            key_outputs = applied_module.library_module.outputs_metadata

            for output_def in key_outputs:
                output_name = output_def.get("name")
                if output_name in outputs:
                    value = outputs[output_name]

                    # Generate variable name for root.hcl
                    # e.g., infra/aws/vpc outputs vpc_id -> vpc_vpc_id or just vpc_id
                    var_name = self._generate_output_var_name(applied_module, output_name)

                    # Update or add to locals block
                    content = self._update_local_variable(content, var_name, value)

        # Write updated root.hcl
        with open(root_hcl_path, 'w') as f:
            f.write(content)

        logger.info(f"Updated root.hcl with outputs from {applied_module.library_module.name}")

    def _generate_output_var_name(self, module, output_name):
        """Generate unique variable name for an output in root.hcl locals."""
        # Simple approach: just use output_name if unique
        # Could prefix with module name if needed: vpc_vpc_id
        return output_name

    def _update_local_variable(self, content, var_name, value):
        """Update or add a variable in the locals block."""
        # Implementation: regex to find and replace, or add if not exists
        # This is simplified - real implementation needs proper HCL parsing
        ...
```

### 3.3 Integrate with Apply Task

**Location**: `bnk-forge/backend/tasks/terraform_tasks.py`

```python
@celery.task
def run_terraform_apply(task_id, module_id, auto_approve=False):
    # ... existing apply logic ...

    if success:
        # Parse outputs from state
        from services.state_parser import TerraformStateParser
        state_path = os.path.join(module_dir, "terraform.tfstate")

        if os.path.exists(state_path):
            parser = TerraformStateParser(state_path)
            state_data = parser.parse()
            outputs = state_data.get("outputs", {})

            # Store outputs in ProjectModule
            module.outputs = {k: v.get("value") for k, v in outputs.items()}
            db.commit()

            # NEW: Update root.hcl with real output values
            from services.root_hcl_service import RootHclService
            root_hcl_service = RootHclService()
            root_hcl_service.update_with_module_outputs(
                project, module, module.outputs
            )
```

---

## Phase 4: UI Enhancements

**Location**: `bnk-forge/frontend-v2/src/components/`
**Effort**: Medium
**Risk**: Low

### 4.1 Update ModuleDetailSheet

```tsx
// components/modules/ModuleDetailSheet.tsx

// Replace hardcoded "No dependencies" with real data
<div>
    <h3 className="font-semibold mb-3">Dependencies</h3>
    {module.dependencies_metadata?.required?.length > 0 ? (
        <div className="space-y-2">
            {module.dependencies_metadata.required.map((dep) => (
                <div key={dep.module} className="flex items-center gap-2 text-sm">
                    <GitBranch className="h-4 w-4" />
                    <span>{dep.module}</span>
                    <span className="text-muted-foreground">- {dep.reason}</span>
                </div>
            ))}
        </div>
    ) : (
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <GitBranch className="h-4 w-4" />
            <span>No dependencies</span>
        </div>
    )}
</div>
```

### 4.2 Add Input Source Display

```tsx
// Show which inputs come from user vs other modules
<div>
    <h3 className="font-semibold mb-3">Inputs</h3>

    {/* User Inputs */}
    <h4 className="text-sm text-muted-foreground mb-2">User Configuration</h4>
    {userInputs.map(input => (
        <InputRow key={input.name} input={input} />
    ))}

    {/* Module Inputs */}
    <h4 className="text-sm text-muted-foreground mb-2 mt-4">From Other Modules</h4>
    {moduleInputs.map(input => (
        <InputRow
            key={input.name}
            input={input}
            status={getInputStatus(input)}  // pending, ready, missing
        />
    ))}
</div>
```

### 4.3 Update API Types

```typescript
// types/index.ts
interface ModuleLibrary {
    // ... existing fields ...
    dependencies_metadata?: {
        required: Array<{ module: string; reason: string }>;
        optional: Array<{ module: string; reason?: string }>;
    };
    inputs_metadata?: {
        required: Array<ModuleInput>;
        optional: Array<ModuleInput>;
    };
    outputs_metadata?: Array<ModuleOutput>;
    deployment_order?: number;
}

interface ModuleInput {
    name: string;
    type: string;
    description: string;
    source: "user" | "module" | "auto";
    from_module?: string;
    from_output?: string;
    default?: any;
}

interface ModuleOutput {
    name: string;
    type: string;
    description: string;
    used_by: string[];
    sensitive: boolean;
}
```

---

## Phase 5: Testing & Validation

### 5.1 Test Cases

1. **Catalog Sync**: Verify module.json is parsed correctly
2. **Dependency Resolution**: Adding EKS auto-detects VPC/Security deps
3. **Input Wiring**: After VPC apply, EKS sees vpc_id as "ready"
4. **root.hcl Update**: Real outputs appear in locals after apply
5. **UI Display**: Dependencies and input sources shown correctly

### 5.2 Integration Test

```python
def test_full_dependency_flow():
    # 1. Sync catalog
    sync_module_catalog(db)

    # 2. Create project
    project = create_project("test-project")

    # 3. Add VPC module
    add_module(project, "infra/aws/vpc")

    # 4. Add EKS module - should detect VPC dependency
    result = add_module(project, "infra/aws/eks")
    assert result.dependencies == [vpc_module.id]

    # 5. Apply VPC
    apply_module(vpc_module)

    # 6. Check root.hcl has vpc_id
    root_hcl = read_root_hcl(project)
    assert "vpc_id" in root_hcl
    assert "vpc-" in root_hcl  # Real value

    # 7. Check EKS inputs are ready
    wiring = InputWiringService(db)
    ready, not_ready = wiring.are_all_inputs_ready(eks_module)
    assert "vpc_id" not in [n["name"] for n in not_ready]
```

---

## Implementation Order

| Phase | Component | Priority | Effort | Dependencies |
|-------|-----------|----------|--------|--------------|
| 1.1 | Parse module.json in catalog sync | P0 | Low | None |
| 1.2 | Add DB columns | P0 | Low | None |
| 1.3 | Migration | P0 | Low | 1.2 |
| 2.1 | Use module.json for deps | P0 | Medium | 1.1 |
| 2.2 | Auto-add dependencies | P1 | Medium | 2.1 |
| 2.3 | Use deployment order | P1 | Low | 1.1 |
| 3.1 | Input wiring service | P0 | High | 1.1, 2.1 |
| 3.2 | root.hcl output updates | P0 | High | 3.1 |
| 3.3 | Integrate with apply | P0 | Medium | 3.2 |
| 4.1 | UI dependencies | P1 | Medium | 1.1 |
| 4.2 | UI input sources | P2 | Medium | 3.1 |
| 4.3 | API types | P1 | Low | 1.2 |
| 5.x | Testing | P0 | Medium | All |

---

## Files to Modify

### bnk-forge Repository

| File | Changes |
|------|---------|
| `backend/models.py` | Add metadata columns to ModuleLibrary |
| `backend/services/module_catalog_service.py` | Parse module.json |
| `backend/services/project_service.py` | Replace MODULE_DEPENDENCY_RULES |
| `backend/services/input_wiring_service.py` | NEW: Input wiring logic |
| `backend/services/root_hcl_service.py` | NEW: root.hcl update logic |
| `backend/routes/project_modules.py` | Use new dep detection, add endpoints |
| `backend/tasks/terraform_tasks.py` | Update root.hcl after apply |
| `frontend-v2/src/types/index.ts` | Add metadata types |
| `frontend-v2/src/components/modules/ModuleDetailSheet.tsx` | Show deps |

### bnk-forge-modules Repository

| File | Changes |
|------|---------|
| `MODULE_METADATA_SCHEMA.md` | Document new fields being used |
| `.agent/DECISIONS.md` | Document this architectural decision |

---

## Success Criteria

1. Adding a module shows its dependencies from module.json
2. Required dependencies are enforced or auto-added
3. After module apply, outputs appear in root.hcl with real values
4. Dependent modules can see which inputs are ready vs pending
5. UI shows accurate dependency and input information
6. Deployment order matches module.json specification

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing projects | High | Add migration, keep backwards compatibility |
| HCL parsing complexity | Medium | Use regex for simple cases, consider hcl2 library |
| Circular dependency in modules | Medium | Validate at catalog sync time |
| Performance with many modules | Low | Cache metadata, lazy load |

---

## Related Documentation

- `bnk-forge-modules/MODULE_METADATA_SCHEMA.md` - Schema definition
- `bnk-forge-modules/DEPENDENCY_GRAPH.md` - Module relationships
- `bnk-forge/.agent/DECISIONS.md` - Architecture decisions
- `bnk-forge/docs/5-reference/module-dependencies.md` - User docs

---

**Next Steps**:
1. Review this plan with stakeholders
2. Create feature branch in bnk-forge
3. Implement Phase 1 (catalog sync)
4. Test with existing modules
5. Proceed to Phase 2

**Document Owner**: Claude Code Agent
**Last Updated**: 2026-01-20
