# dssm

## Description

BNK Application module for dssm.

## Category

- **Type**: BNK Application
- **Provider**: Cloud-agnostic
- **Workflow Compatibility**: Greenfield, Partial, Minimal

## Requirements

- Terraform >= 1.0
- Terragrunt >= 0.45

## Usage

```hcl
terraform {
  source = "git::https://github.com/JLCode-tech/bnk-forge-modules.git//bnk/dssm?ref=v1.0.0"
}

inputs = {
  # See variables below
}
```

## Inputs

See [variables.tf](variables.tf) for all available inputs.

## Outputs

See [outputs.tf](outputs.tf) for all available outputs.

## Dependencies

Check the module's `dependencies` block in terragrunt.hcl for required dependencies.

## Testing Status

⚪ Not tested - This module has not yet been validated by automated testing.

## Version

Current version: 1.0.0

## Maintainer

BNK-Forge Team
