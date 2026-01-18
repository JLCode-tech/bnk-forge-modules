# Code Patterns and Conventions - BNK-Forge Modules

Last Updated: 2026-01-18

## Overview

This document captures coding patterns, conventions, and best practices for the bnk-forge-modules repository. Follow these patterns for consistency and maintainability.

---

## File Structure

### Standard Module Structure

Every module MUST include these files:

```
module-name/
├── main.tf              # Primary Terraform resources
├── variables.tf         # Input variables with descriptions
├── outputs.tf           # Output values with descriptions
├── versions.tf          # Terraform and provider version constraints
├── module.json          # BNK-Forge metadata (JSON format)
└── README.md            # Module documentation with examples
```

### Optional Module Files

```
module-name/
├── locals.tf            # Local values (for complex transformations)
├── data.tf              # Data sources (optional, can be in main.tf)
├── scripts/             # Helper scripts (bash, python, etc.)
├── manifests/           # Kubernetes manifest templates
└── templates/           # Template files for user_data, configs, etc.
```

---

## Terraform Patterns

### Resource Naming

**Pattern**: Use project_name prefix for all resources

```hcl
# Good
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

# Bad
resource "aws_vpc" "my_vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "my-vpc"  # Missing project_name
  }
}
```

### Variable Definitions

**Pattern**: Include type, description, and validation where appropriate

```hcl
# Good
variable "capacity_type" {
  description = "Capacity type for the node group"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "Capacity type must be either ON_DEMAND or SPOT."
  }
}

# Bad
variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"
  # Missing description and validation
}
```

### Output Definitions

**Pattern**: Include descriptions for all outputs

```hcl
# Good
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
  sensitive   = false
}

# Bad
output "vpc_id" {
  value = aws_vpc.main.id  # Missing description
}
```

### Local Values

**Pattern**: Use locals for complex transformations and repeated values

```hcl
# Good
locals {
  teem_urls = {
    production = {
      cert_url        = "https://product.apis.f5.com/ee/v1"
      entitlement_url = "https://product-s.apis.f5.com/ee/v1"
    }
    test = {
      cert_url        = "https://product-tst.apis.f5networks.net/ee/v1"
      entitlement_url = "https://product-s-tst.apis.f5networks.net/ee/v1"
    }
  }

  selected_teem = local.teem_urls[var.license_environment]
}

# Use in resource
license_config = {
  teemCertUrl = local.selected_teem.cert_url
}
```

### Tagging Strategy

**Pattern**: Use merge() to combine common_tags with resource-specific tags

```hcl
# Good
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.public_subnet_cidr

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-public-jumphost"
    Type = "Public"
  })
}

# Pattern for Kubernetes resources
tags = merge(var.common_tags, {
  Name = "${var.project_name}-private-external-a"
  Type = "Private"
  "kubernetes.io/cluster/${var.project_name}-cluster" = "owned"
  "kubernetes.io/role/internal-elb" = "1"
})
```

### Kubernetes Resources (via kubernetes provider)

**Pattern**: Use kubernetes_namespace with proper labels

```hcl
resource "kubernetes_namespace" "flo" {
  metadata {
    name = var.flo_namespace

    labels = merge(var.common_labels, {
      name    = var.flo_namespace
      purpose = "f5-lifecycle-operator"
    })
  }
}
```

### Helm Releases

**Pattern**: Use yamlencode() for values, include dependencies

```hcl
resource "helm_release" "flo" {
  depends_on = [
    kubernetes_namespace.flo,
    var.cert_manager_ready,
    var.far_setup_complete
  ]

  name       = "flo"
  repository = var.flo_chart_repository
  chart      = "f5-lifecycle-operator"
  version    = var.flo_version
  namespace  = var.flo_namespace

  timeout = 600
  wait    = true

  values = [
    yamlencode({
      image = {
        repository = var.image_registry
        pullPolicy = "IfNotPresent"
      }

      imagePullSecrets = [
        { name = var.far_secret_name }
      ]

      # More configuration...
    })
  ]
}
```

### Dependencies

**Pattern**: Use explicit depends_on for cross-module dependencies

```hcl
# Good - Explicit dependency
resource "helm_release" "component" {
  depends_on = [
    var.prerequisite_ready,
    kubernetes_namespace.target
  ]

  # Resource configuration...
}

# For module outputs that represent readiness
output "module_ready" {
  description = "Signal that this module is ready for dependent modules"
  value       = true
  depends_on  = [
    resource.critical_resource
  ]
}
```

---

## Module Metadata (module.json)

### Standard Schema

```json
{
  "module": {
    "name": "Friendly Module Name",
    "path": "category/cloud/module-name",
    "version": "1.0.0",
    "layer": "infrastructure | kubernetes | application",
    "category": "network | compute | storage | security | gateway | policy",
    "description": "Clear description of what this module does",
    "cloud_specific": true | false,
    "supported_platforms": ["aws", "azure", "gcp", "kubernetes"]
  },
  "dependencies": {
    "required": ["module/path1", "module/path2"],
    "optional": ["module/path3"]
  },
  "inputs": {
    "required": [
      {
        "name": "variable_name",
        "type": "string | number | bool | list(type) | map(type)",
        "description": "Clear description",
        "source": "user | module_output | computed",
        "example": "example-value"
      }
    ],
    "optional": [
      {
        "name": "optional_var",
        "type": "string",
        "description": "Description",
        "default": "default-value",
        "source": "user"
      }
    ]
  },
  "outputs": {
    "key_outputs": [
      {
        "name": "output_name",
        "type": "string",
        "description": "What this output provides",
        "used_by": ["module/path1", "module/path2"],
        "sensitive": false
      }
    ]
  },
  "providers": {
    "required": ["provider1", "provider2"],
    "optional": []
  },
  "deployment": {
    "order": 1,
    "estimated_time": "5 minutes",
    "requires_user_input": true | false,
    "sensitive_inputs": ["jwt_token", "api_key"]
  }
}
```

### Versioning

- Use semantic versioning: MAJOR.MINOR.PATCH
- Increment MAJOR for breaking changes
- Increment MINOR for new features (backward compatible)
- Increment PATCH for bug fixes

---

## Script Patterns

### Bash Scripts

**Pattern**: Include error handling and logging

```bash
#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script header with purpose
# Description: What this script does
# Usage: ./script-name.sh [args]

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

# Main logic
main() {
    log "Starting operation..."

    # Check prerequisites
    if ! command -v required_tool &> /dev/null; then
        error "required_tool not found"
    fi

    # Do work
    log "Completed successfully"
}

main "$@"
```

### Python Scripts

**Pattern**: Use argparse, logging, and type hints

```python
#!/usr/bin/env python3
"""
Script description here.

Usage:
    python script-name.py --arg value
"""

import logging
import argparse
from typing import Dict, List

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def main(args: argparse.Namespace) -> None:
    """Main entry point."""
    logger.info("Starting operation...")
    # Implementation
    logger.info("Completed successfully")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Script description")
    parser.add_argument("--arg", required=True, help="Argument description")
    args = parser.parse_args()

    main(args)
```

---

## Documentation Patterns

### Module README.md

**Standard Structure**:

```markdown
# Module Name

Brief description of what this module does.

## Overview

More detailed explanation of the module's purpose and use cases.

## Requirements

- Terraform >= 1.5.0
- Provider requirements
- Prerequisites (other modules, services, etc.)

## Usage

\```hcl
module "example" {
  source = "path/to/module"

  # Required variables
  project_name = "my-project"
  vpc_cidr     = "10.0.0.0/16"

  # Optional variables
  common_tags = {
    Environment = "production"
  }
}
\```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| project_name | Name of the project | string | n/a | yes |
| vpc_cidr | CIDR block for VPC | string | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | ID of the VPC |
| subnet_ids | List of subnet IDs |

## Dependencies

### Required
- `infra/aws/vpc` - Provides networking

### Optional
- None

## Notes

- Special considerations
- Known limitations
- Best practices

## Examples

Link to examples/ directory or inline examples.
```

### Inline Comments

**Good Comments** (explain WHY):
```hcl
# Use static CPU manager policy for predictable performance with DPDK
cpu_manager_policy = "static"

# Wait 30s for operator to become ready before proceeding
create_duration = "30s"
```

**Bad Comments** (explain WHAT - code is self-documenting):
```hcl
# Set CPU manager policy to static
cpu_manager_policy = "static"

# Create VPC
resource "aws_vpc" "main" { ... }
```

---

## Development Commands

### Terraform

```bash
# Format all Terraform files
terraform fmt -recursive

# Check formatting (CI)
terraform fmt -check -recursive

# Validate all modules
cd module-dir && terraform validate

# Initialize module
terraform init
```

### Validation

```bash
# Validate all module.json files
find . -name "module.json" -exec jq empty {} \;

# Check for required module files
for dir in infra/*/* k8s/* bnk/*; do
  if [ -d "$dir" ]; then
    echo "Checking $dir"
    ls "$dir"/{main,variables,outputs,versions}.tf module.json README.md
  fi
done
```

### Git

```bash
# Check for sensitive files before committing
git status | grep -iE "jwt|token|secret|password|credential|key|pem"

# View changes in a specific module
git diff -- infra/aws/vpc/

# Commit with conventional format
git commit -m "feat(infra/vpc): add support for IPv6"
```

---

## Common Gotchas

### 1. Module Dependencies

**Problem**: Terraform doesn't know about implicit dependencies between modules.

**Solution**: Use explicit outputs and depends_on:

```hcl
# In prerequisite module
output "module_ready" {
  description = "Signal that module is ready"
  value       = true
  depends_on  = [helm_release.component]
}

# In dependent module
variable "prerequisite_ready" {
  description = "Dependency from prerequisite module"
  type        = bool
}

resource "example" "dependent" {
  depends_on = [var.prerequisite_ready]
  # ...
}
```

### 2. Kubernetes Tagging

**Problem**: EKS requires specific tags on subnets.

**Solution**: Always include cluster tags:

```hcl
tags = {
  "kubernetes.io/cluster/${var.project_name}-cluster" = "owned"
  "kubernetes.io/role/internal-elb" = "1"  # For private subnets
}
```

### 3. Sensitive Values

**Problem**: Accidentally committing secrets.

**Solution**:
- Check .gitignore patterns
- Use `sensitive = true` in outputs
- Never hardcode secrets
- Use external secret management

### 4. Provider Versions

**Problem**: Different modules using incompatible provider versions.

**Solution**: Use version constraints in versions.tf:

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

### 5. Helm Values Formatting

**Problem**: Complex Helm values can be error-prone.

**Solution**: Use yamlencode() for proper YAML generation:

```hcl
values = [
  yamlencode({
    key1 = value1
    nested = {
      key2 = value2
    }
  })
]
```

---

## Security Best Practices

### 1. No Hardcoded Secrets

```hcl
# Bad
variable "api_key" {
  default = "secret-key-12345"  # NEVER DO THIS
}

# Good
variable "api_key" {
  description = "API key from external source"
  type        = string
  sensitive   = true
  # No default
}
```

### 2. Secure Defaults

```hcl
# Good - Secure by default
variable "enable_public_access" {
  description = "Allow public access to cluster"
  type        = bool
  default     = false  # Secure default
}
```

### 3. Least Privilege IAM

```hcl
# Good - Specific permissions only
resource "aws_iam_role_policy" "example" {
  policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances",
        "ec2:DescribeNetworkInterfaces"
      ]
      Resource = "*"  # Only if absolutely necessary
    }]
  })
}
```

---

## Performance Patterns

### Resource Counts

```hcl
# Good - Use count for multiple similar resources
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-${count.index}"
  }
}

# Or use for_each for named resources
resource "aws_subnet" "private" {
  for_each = var.subnet_config

  vpc_id     = aws_vpc.main.id
  cidr_block = each.value.cidr

  tags = {
    Name = "${var.project_name}-${each.key}"
  }
}
```

---

## Testing Patterns

### Module Validation

```bash
# Validate module in isolation
cd infra/aws/vpc
terraform init
terraform validate

# Check plan (dry run)
terraform plan -var-file=test.tfvars
```

### Integration Testing

```bash
# Test module with actual deployment (non-production)
cd test-environment
terragrunt plan
terragrunt apply
# Verify resources
terragrunt destroy
```

---

## Questions or Additions

If you encounter patterns not documented here:
1. Add them to this file
2. Update `.agent/CURRENT_WORK.md`
3. Reference in commit message

Keep this file updated as the project evolves.
