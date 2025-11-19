# network-setup

## Description

Kubernetes module for network configuration - sets up network policies, NetworkAttachmentDefinitions for Multus.

## Category

- **Type**: Kubernetes
- **Provider**: Cloud-agnostic
- **Workflow Compatibility**: Greenfield, Partial

## Requirements

- Terraform >= 1.0
- Terragrunt >= 0.45
- Kubernetes cluster with Multus CNI

## Usage

```hcl
terraform {
  source = "git::https://github.com/JLCode-tech/bnk-forge-modules.git//k8s/network-setup?ref=v1.0.0"
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
