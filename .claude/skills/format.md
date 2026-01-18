# /format - Format All Terraform Files

## When to Use

Use this skill to format all Terraform files according to Terraform style conventions:
- Before committing changes
- After making manual edits to .tf files
- When validation reports formatting issues
- To ensure consistent code style

## What This Skill Does

Automatically formats all Terraform files in the repository to match Terraform's canonical formatting style.

## Step-by-Step Instructions

### 1. Run Terraform Format

Format all Terraform files recursively:

```bash
terraform fmt -recursive
```

**Expected Output**: List of files that were formatted
```
infra/aws/vpc/main.tf
infra/aws/vpc/variables.tf
bnk/flo/main.tf
```

**If No Output**: All files were already properly formatted ✓

### 2. Verify Formatting

Check that all files are now properly formatted:

```bash
terraform fmt -check -recursive
```

**Expected Output**: No output (all files formatted correctly)

**If Output**: Files listed need formatting (run step 1 again)

### 3. Review Changes

If files were modified, review the changes:

```bash
git diff
```

This will show what formatting changes were made. Common changes include:
- Alignment of equals signs
- Spacing in blocks
- Line breaks in complex expressions

### 4. Summary

Provide a summary of the formatting operation:

```
✓ Formatted X files
✓ All files now properly formatted
```

## Example Output

```
$ terraform fmt -recursive
infra/aws/vpc/main.tf
infra/aws/eks/variables.tf
bnk/flo/main.tf

$ terraform fmt -check -recursive
(no output - all files formatted)

✓ 3 files formatted successfully
```

## Troubleshooting

### Issue: "terraform: command not found"

**Solution**: Terraform is not installed or not in PATH
```bash
which terraform
# Install Terraform 1.5+ if not found
```

### Issue: Files still showing as unformatted after running

**Solution**: There may be syntax errors preventing formatting
```bash
# Check for syntax errors
terraform validate
```

### Issue: Format conflicts with existing style

**Solution**: Terraform's format is canonical - accept the changes
- The repository follows Terraform's official formatting
- Commit the formatted changes
- Future edits will maintain the same style

## What Gets Formatted

Terraform fmt automatically formats:
- Indentation (2 spaces)
- Alignment of equals signs in arguments
- Spacing around operators
- Line breaks in complex expressions
- Attribute ordering (alphabetical within blocks)

## What Doesn't Get Formatted

Terraform fmt does NOT change:
- Comments
- Resource/variable/output names
- String contents
- Logic or functionality

## Related

- `/validate` - Validate all modules
- `.agent/PATTERNS.md` - Code conventions and patterns
