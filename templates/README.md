# BNK-Forge Configuration Templates

This directory contains template files for generating project-specific Terragrunt configurations.

## Directory Structure

```
templates/
├── root-hcl/              # Terragrunt root.hcl templates
│   ├── aws-full-stack.hcl      # AWS VPC → EKS → BNK full deployment
│   └── existing-k8s-bnk.hcl    # Add BNK to existing Kubernetes
├── variables/             # Terraform variables templates
│   └── aws-full-stack.tfvars   # Variables for AWS full stack
└── backend/               # Backend configuration templates
    ├── s3.hcl                  # AWS S3 backend (recommended for AWS)
    └── local.hcl               # Local backend (dev/on-prem)
```

## Template Usage

### 1. Root.hcl Templates

Root.hcl files define the module dependencies, provider configurations, and state management.

**Available Templates:**
- `aws-full-stack.hcl` - Complete AWS infrastructure + BNK deployment
- `existing-k8s-bnk.hcl` - BNK deployment on existing Kubernetes

**Template Variables (replaced by bnk-forge):**
- `{{PROJECT_NAME}}` - Project identifier
- `{{ENVIRONMENT}}` - Environment (dev, staging, prod)
- `{{AWS_REGION}}` - AWS region (for AWS deployments)
- `{{CLUSTER_NAME}}` - Kubernetes cluster name
- `{{KUBECONFIG_PATH}}` - Path to kubeconfig (for existing K8s)
- `{{MODULE_PATH}}` - Relative path to specific module
- `{{SKIP_*}}` - Conditional module inclusion flags

### 2. Variables Templates

Variables templates provide all required and optional inputs for modules.

**Template Variables:**
- `{{PROJECT_NAME}}` - Project name
- `{{ENVIRONMENT}}` - Environment name
- `{{AWS_REGION}}` - AWS region
- `{{USER_IP}}` - User's public IP for security group access
- `{{SPK_VERSION}}` - F5 SPK manifest version
- `{{FAR_KEY_PATH}}` - Path to F5 FAR service account JSON

### 3. Backend Templates

Backend templates configure Terraform state storage.

**S3 Backend (`s3.hcl`):**
- For AWS deployments
- Provides state locking via DynamoDB
- Encryption enabled by default

**Local Backend (`local.hcl`):**
- For development/on-prem deployments
- No state locking (single-user only)
- State stored in local filesystem

## Template Selection Guide

### Scenario A: "I have nothing, deploy everything on AWS"
**Use:**
- `root-hcl/aws-full-stack.hcl`
- `variables/aws-full-stack.tfvars`
- `backend/s3.hcl`

**Deploys:** VPC → Security → EKS → Storage → BNK (far-setup → cert-manager → flo → gateway API)

### Scenario B: "I have AWS EKS, add BNK"
**Use:**
- `root-hcl/existing-k8s-bnk.hcl`
- `variables/existing-k8s-bnk.tfvars` (to be created)
- `backend/s3.hcl` or `local.hcl`

**Deploys:** BNK components only (far-setup → cert-manager → flo → gateway API)

### Scenario C: "I have on-prem Kubernetes, add BNK"
**Use:**
- `root-hcl/existing-k8s-bnk.hcl`
- `variables/existing-k8s-bnk.tfvars` (to be created)
- `backend/local.hcl` or `consul.hcl` (to be created)

**Deploys:** BNK components only using kubeconfig

## Template Processing

The bnk-forge tool processes templates in this order:

1. **Module Selection** - User selects which modules to deploy
2. **Dependency Resolution** - System calculates required and optional dependencies
3. **Template Selection** - System chooses appropriate template based on scenario
4. **Variable Substitution** - Replace template variables with user-provided values
5. **File Generation** - Generate root.hcl, variables.tfvars, backend.hcl in project directory
6. **Validation** - Validate generated configuration

## Adding New Templates

To add a new template:

1. Create template file in appropriate subdirectory
2. Use `{{VARIABLE}}` syntax for replaceable values
3. Document template variables in this README
4. Add template to selection guide above
5. Update bnk-forge backend to recognize new template

## Example: Generated Project Structure

After processing templates, user project looks like:

```
my-bnk-project/
├── terragrunt.hcl           # Root configuration (from template)
├── variables.tfvars         # User-specific values (from template)
├── backend.hcl              # Backend config (from template)
├── infra/
│   └── aws/
│       ├── vpc/
│       │   └── terragrunt.hcl
│       ├── security/
│       │   └── terragrunt.hcl
│       └── eks/
│           └── terragrunt.hcl
├── k8s/
│   └── cert-manager/
│       └── terragrunt.hcl
└── bnk/
    ├── far-setup/
    │   └── terragrunt.hcl
    ├── flo/
    │   └── terragrunt.hcl
    └── bnk-gatewayclass/
        └── terragrunt.hcl
```

Each module's `terragrunt.hcl` includes the root configuration and adds module-specific inputs.
