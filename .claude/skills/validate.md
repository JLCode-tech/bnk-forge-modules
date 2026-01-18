# /validate - Validate All Terraform Modules

## When to Use

Use this skill when you need to validate all Terraform modules in the repository:
- After making changes to any module
- Before committing code
- During CI/CD pipeline execution
- When checking module integrity

## What This Skill Does

1. Validates Terraform syntax and configuration in all modules
2. Checks Terraform formatting
3. Validates module.json schema
4. Reports any errors or issues found

## Step-by-Step Instructions

### 1. Format Check

Run Terraform format check across all files:

```bash
terraform fmt -check -recursive
```

**Expected Output**: Should complete with no output (all files are formatted)

**If Errors**: Files need formatting. Run `/format` skill to fix.

### 2. Module Validation

Validate each module directory:

```bash
# AWS Infrastructure Modules
for module in infra/aws/*/; do
  echo "=== Validating $module ==="
  cd "$module"
  terraform init -backend=false > /dev/null 2>&1
  terraform validate
  cd - > /dev/null
done

# Kubernetes Modules
for module in k8s/*/; do
  echo "=== Validating $module ==="
  cd "$module"
  terraform init -backend=false > /dev/null 2>&1
  terraform validate
  cd - > /dev/null
done

# BNK Modules
for module in bnk/*/; do
  echo "=== Validating $module ==="
  cd "$module"
  terraform init -backend=false > /dev/null 2>&1
  terraform validate
  cd - > /dev/null
done
```

**Expected Output**: "Success! The configuration is valid." for each module

**If Errors**: Review the error message and fix the Terraform code

### 3. Validate module.json Files

Check all module.json files are valid JSON:

```bash
echo "=== Validating module.json files ==="
find infra k8s bnk -name "module.json" -type f | while read -r file; do
  echo "Checking $file"
  jq empty "$file" 2>&1 || echo "ERROR: Invalid JSON in $file"
done
```

**Expected Output**: No errors (jq will be silent on valid JSON)

**If Errors**: Fix the JSON syntax in the reported file

### 4. Check for Required Files

Verify all modules have required files:

```bash
echo "=== Checking for required module files ==="
for dir in infra/*/* k8s/* bnk/*; do
  if [ -d "$dir" ] && [ -f "$dir/module.json" ]; then
    echo "Checking $dir"
    missing=""
    [ ! -f "$dir/main.tf" ] && missing="$missing main.tf"
    [ ! -f "$dir/variables.tf" ] && missing="$missing variables.tf"
    [ ! -f "$dir/outputs.tf" ] && missing="$missing outputs.tf"
    [ ! -f "$dir/versions.tf" ] && missing="$missing versions.tf"
    [ ! -f "$dir/README.md" ] && missing="$missing README.md"

    if [ -n "$missing" ]; then
      echo "  ❌ Missing:$missing"
    else
      echo "  ✓ Complete"
    fi
  fi
done
```

**Expected Output**: "✓ Complete" for all modules

**If Errors**: Create missing files using patterns from `.agent/PATTERNS.md`

## Troubleshooting

### Issue: "terraform: command not found"

**Solution**: Terraform is not installed or not in PATH
```bash
which terraform
# If not found, install Terraform 1.5+
```

### Issue: "jq: command not found"

**Solution**: jq is not installed
```bash
which jq
# If not found, install jq
```

### Issue: Module validation fails with provider errors

**Solution**: Some modules require specific providers
```bash
# Initialize the module properly
cd module-dir
terraform init
terraform validate
```

### Issue: Format check shows many files

**Solution**: Run the format skill
```bash
# Use the /format skill to fix formatting
```

## Summary Report

After running all validation steps, provide a summary:

```
✓ Terraform formatting: PASS
✓ Module validation: X/Y modules validated successfully
✓ module.json validation: All files valid
✓ Required files check: All modules complete
```

## Related

- `/format` - Format Terraform files
- `/check-modules` - More detailed module structure check
- `.agent/PATTERNS.md` - Code patterns and standards
