# /check-modules - Verify Module Structure and Metadata

## When to Use

Use this skill for comprehensive module structure validation:
- After creating new modules
- Before releasing module updates
- During code review
- To verify module standards compliance

## What This Skill Does

Performs deep validation of module structure:
1. Checks for required files
2. Validates module.json schema compliance
3. Verifies README.md completeness
4. Checks for proper documentation
5. Validates dependency declarations

## Step-by-Step Instructions

### 1. Check Required Files

Verify each module has all required files:

```bash
echo "=== Checking Module Structure ==="
for category in infra/aws infra/azure infra/gcp k8s bnk; do
  if [ ! -d "$category" ]; then
    continue
  fi

  echo ""
  echo "Category: $category"
  echo "----------------------------------------"

  find "$category" -name "module.json" -type f | while read -r json_file; do
    module_dir=$(dirname "$json_file")
    module_name=$(basename "$module_dir")

    echo "📦 $module_dir"

    # Check required files
    errors=0

    [ ! -f "$module_dir/main.tf" ] && echo "  ❌ Missing main.tf" && errors=$((errors+1))
    [ ! -f "$module_dir/variables.tf" ] && echo "  ❌ Missing variables.tf" && errors=$((errors+1))
    [ ! -f "$module_dir/outputs.tf" ] && echo "  ❌ Missing outputs.tf" && errors=$((errors+1))
    [ ! -f "$module_dir/versions.tf" ] && echo "  ❌ Missing versions.tf" && errors=$((errors+1))
    [ ! -f "$module_dir/README.md" ] && echo "  ❌ Missing README.md" && errors=$((errors+1))

    if [ $errors -eq 0 ]; then
      echo "  ✓ All required files present"
    fi
  done
done
```

### 2. Validate module.json Schema

Check module.json files for required fields:

```bash
echo ""
echo "=== Validating module.json Schema ==="
find infra k8s bnk -name "module.json" -type f | while read -r json_file; do
  echo "Checking: $json_file"

  # Validate JSON syntax
  if ! jq empty "$json_file" 2>/dev/null; then
    echo "  ❌ Invalid JSON syntax"
    continue
  fi

  # Check required fields
  module_name=$(jq -r '.module.name // empty' "$json_file")
  module_path=$(jq -r '.module.path // empty' "$json_file")
  module_version=$(jq -r '.module.version // empty' "$json_file")
  module_desc=$(jq -r '.module.description // empty' "$json_file")

  errors=0
  [ -z "$module_name" ] && echo "  ❌ Missing module.name" && errors=$((errors+1))
  [ -z "$module_path" ] && echo "  ❌ Missing module.path" && errors=$((errors+1))
  [ -z "$module_version" ] && echo "  ❌ Missing module.version" && errors=$((errors+1))
  [ -z "$module_desc" ] && echo "  ❌ Missing module.description" && errors=$((errors+1))

  # Check version format (should be semver)
  if [ -n "$module_version" ]; then
    if ! echo "$module_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "  ⚠️  Version '$module_version' doesn't follow semver (X.Y.Z)"
    fi
  fi

  if [ $errors -eq 0 ]; then
    echo "  ✓ Schema valid: $module_name v$module_version"
  fi
done
```

### 3. Check README Completeness

Verify README files have required sections:

```bash
echo ""
echo "=== Checking README Completeness ==="
find infra k8s bnk -name "README.md" -path "*/[!archived]*" -type f | while read -r readme; do
  module_dir=$(dirname "$readme")
  echo "Checking: $readme"

  missing_sections=""

  # Check for required sections
  grep -q "## Overview\|## Description" "$readme" || missing_sections="$missing_sections Overview"
  grep -q "## Requirements" "$readme" || missing_sections="$missing_sections Requirements"
  grep -q "## Usage" "$readme" || missing_sections="$missing_sections Usage"
  grep -q "## Inputs" "$readme" || missing_sections="$missing_sections Inputs"
  grep -q "## Outputs" "$readme" || missing_sections="$missing_sections Outputs"

  if [ -n "$missing_sections" ]; then
    echo "  ⚠️  Missing sections:$missing_sections"
  else
    echo "  ✓ All required sections present"
  fi
done
```

### 4. Verify Dependencies Match

Check that dependencies in module.json match actual usage:

```bash
echo ""
echo "=== Checking Dependency Declarations ==="
find infra k8s bnk -name "module.json" -type f | while read -r json_file; do
  module_dir=$(dirname "$json_file")
  module_name=$(jq -r '.module.name' "$json_file")

  echo "Module: $module_name"

  # Get declared dependencies
  required_deps=$(jq -r '.dependencies.required[]? // empty' "$json_file")

  if [ -n "$required_deps" ]; then
    echo "  Declared dependencies:"
    echo "$required_deps" | while read -r dep; do
      echo "    - $dep"
    done
  else
    echo "  No dependencies declared"
  fi

  # Check for variable references that might indicate dependencies
  # (This is a heuristic check)
  if [ -f "$module_dir/variables.tf" ]; then
    dependency_vars=$(grep -E "description.*from.*module|dependency" "$module_dir/variables.tf" | head -3)
    if [ -n "$dependency_vars" ]; then
      echo "  Variables suggesting dependencies:"
      echo "$dependency_vars" | sed 's/^/    /'
    fi
  fi

  echo ""
done
```

### 5. Summary Report

Generate summary of module health:

```bash
echo ""
echo "=== Module Health Summary ==="
total_modules=$(find infra k8s bnk -name "module.json" -not -path "*/archived/*" | wc -l | tr -d ' ')
echo "Total modules: $total_modules"

# Count modules by category
echo ""
echo "By category:"
echo "  AWS Infrastructure: $(find infra/aws -name "module.json" | wc -l | tr -d ' ')"
echo "  Kubernetes: $(find k8s -name "module.json" | wc -l | tr -d ' ')"
echo "  BNK: $(find bnk -name "module.json" -not -path "*/archived/*" | wc -l | tr -d ' ')"

echo ""
echo "✓ Module structure check complete"
```

## What This Checks

### Required Files
- `main.tf` - Primary resources
- `variables.tf` - Input variables
- `outputs.tf` - Output values
- `versions.tf` - Provider versions
- `module.json` - BNK-Forge metadata
- `README.md` - Documentation

### module.json Schema
- `module.name` - Display name
- `module.path` - Path in repository
- `module.version` - Semantic version
- `module.description` - Clear description
- `module.layer` - infrastructure/kubernetes/application
- `dependencies` - Required and optional modules

### README Sections
- Overview/Description
- Requirements
- Usage examples
- Inputs table
- Outputs table

## Troubleshooting

### Issue: Missing files in a module

**Solution**: Create the missing files using templates from `.agent/PATTERNS.md`

```bash
# Copy from templates/ directory or another similar module
cp templates/main.tf infra/aws/new-module/
```

### Issue: Invalid module.json

**Solution**: Fix JSON syntax or add missing fields

```bash
# Validate JSON
jq . module.json

# Check against schema in MODULE_METADATA_SCHEMA.md
```

### Issue: Incomplete README

**Solution**: Add missing sections following the pattern in `.agent/PATTERNS.md`

## Related

- `/validate` - Terraform validation
- `.agent/PATTERNS.md` - Module structure patterns
- `MODULE_METADATA_SCHEMA.md` - Full schema documentation
- `templates/` - Module templates
