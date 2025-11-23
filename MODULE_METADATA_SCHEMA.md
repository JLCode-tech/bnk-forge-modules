# Module Metadata Schema

Each module should have a `module.json` file that describes its dependencies, inputs, and outputs for automated configuration generation.

## Schema Definition

```json
{
  "module": {
    "name": "string",
    "path": "string",
    "version": "string",
    "layer": "infrastructure|kubernetes|bnk-foundation|bnk-platform|bnk-gateway|bnk-policy",
    "category": "network|security|compute|storage|platform|application",
    "description": "string",
    "cloud_specific": boolean,
    "supported_platforms": ["aws", "azure", "gcp", "on-prem", "any"]
  },
  "dependencies": {
    "required": [
      {
        "module": "string (module path)",
        "reason": "string (why it's required)"
      }
    ],
    "optional": [
      {
        "module": "string (module path)",
        "reason": "string (why it's recommended)",
        "provides": "string (what capability it adds)"
      }
    ]
  },
  "inputs": {
    "required": [
      {
        "name": "string",
        "type": "string|number|boolean|list|map|object",
        "description": "string",
        "source": "user|module|auto",
        "from_module": "string (if source=module)",
        "from_output": "string (if source=module)",
        "example": "any"
      }
    ],
    "optional": [
      {
        "name": "string",
        "type": "string|number|boolean|list|map|object",
        "description": "string",
        "default": "any",
        "source": "user|module|auto",
        "from_module": "string (optional)",
        "from_output": "string (optional)"
      }
    ]
  },
  "outputs": {
    "key_outputs": [
      {
        "name": "string",
        "type": "string",
        "description": "string",
        "used_by": ["string (list of modules that consume this)"],
        "sensitive": boolean
      }
    ]
  },
  "providers": {
    "required": ["kubernetes", "helm", "aws", etc.],
    "optional": []
  },
  "backend": {
    "recommendations": {
      "aws": "s3",
      "azure": "azurerm",
      "gcp": "gcs",
      "on-prem": "local|consul"
    }
  },
  "deployment": {
    "order": number,
    "estimated_time": "string (e.g., '5 minutes')",
    "requires_user_input": boolean,
    "sensitive_inputs": ["string (list of sensitive variable names)"]
  }
}
```

## Example: infra/aws/vpc

```json
{
  "module": {
    "name": "AWS VPC",
    "path": "infra/aws/vpc",
    "version": "1.0.0",
    "layer": "infrastructure",
    "category": "network",
    "description": "Creates AWS VPC with public and private subnets across 2 availability zones",
    "cloud_specific": true,
    "supported_platforms": ["aws"]
  },
  "dependencies": {
    "required": [],
    "optional": []
  },
  "inputs": {
    "required": [
      {
        "name": "project_name",
        "type": "string",
        "description": "Name of the project - used for resource naming",
        "source": "user",
        "example": "my-bnk-project"
      },
      {
        "name": "environment",
        "type": "string",
        "description": "Environment name (dev, staging, prod)",
        "source": "user",
        "example": "dev"
      },
      {
        "name": "vpc_cidr",
        "type": "string",
        "description": "CIDR block for VPC",
        "source": "user",
        "example": "10.0.0.0/16"
      },
      {
        "name": "public_subnet_cidr",
        "type": "string",
        "description": "CIDR block for public subnet (jumphost)",
        "source": "user",
        "example": "10.0.1.0/24"
      },
      {
        "name": "private_external_subnet_a_cidr",
        "type": "string",
        "description": "CIDR block for private external subnet in AZ-A",
        "source": "user",
        "example": "10.0.10.0/24"
      },
      {
        "name": "private_external_subnet_b_cidr",
        "type": "string",
        "description": "CIDR block for private external subnet in AZ-B",
        "source": "user",
        "example": "10.0.11.0/24"
      },
      {
        "name": "private_internal_subnet_a_cidr",
        "type": "string",
        "description": "CIDR block for private internal subnet in AZ-A",
        "source": "user",
        "example": "10.0.20.0/24"
      },
      {
        "name": "private_internal_subnet_b_cidr",
        "type": "string",
        "description": "CIDR block for private internal subnet in AZ-B",
        "source": "user",
        "example": "10.0.21.0/24"
      }
    ],
    "optional": [
      {
        "name": "common_tags",
        "type": "map(string)",
        "description": "Common tags to apply to all resources",
        "default": {},
        "source": "user"
      }
    ]
  },
  "outputs": {
    "key_outputs": [
      {
        "name": "vpc_id",
        "type": "string",
        "description": "ID of the VPC",
        "used_by": ["infra/aws/security", "infra/aws/eks", "infra/aws/high-performance-nodes"],
        "sensitive": false
      },
      {
        "name": "vpc_cidr_block",
        "type": "string",
        "description": "CIDR block of the VPC",
        "used_by": ["infra/aws/security"],
        "sensitive": false
      },
      {
        "name": "public_subnet_id",
        "type": "string",
        "description": "ID of the public subnet",
        "used_by": ["infra/aws/security"],
        "sensitive": false
      },
      {
        "name": "private_external_subnet_ids",
        "type": "list(string)",
        "description": "IDs of the private external subnets",
        "used_by": ["infra/aws/eks"],
        "sensitive": false
      },
      {
        "name": "private_internal_subnet_ids",
        "type": "list(string)",
        "description": "IDs of the private internal subnets",
        "used_by": ["infra/aws/eks"],
        "sensitive": false
      },
      {
        "name": "availability_zones",
        "type": "list(string)",
        "description": "Availability zones used by the VPC",
        "used_by": ["k8s/network-setup", "bnk/f5-controller"],
        "sensitive": false
      }
    ]
  },
  "providers": {
    "required": ["aws"],
    "optional": []
  },
  "backend": {
    "recommendations": {
      "aws": "s3"
    }
  },
  "deployment": {
    "order": 1,
    "estimated_time": "5 minutes",
    "requires_user_input": true,
    "sensitive_inputs": []
  }
}
```

## Example: bnk/flo

```json
{
  "module": {
    "name": "F5 Lifecycle Operator (FLO)",
    "path": "bnk/flo",
    "version": "1.0.0",
    "layer": "bnk-platform",
    "category": "platform",
    "description": "Deploys F5 Lifecycle Operator to manage BNK components and CRDs",
    "cloud_specific": false,
    "supported_platforms": ["any"]
  },
  "dependencies": {
    "required": [
      {
        "module": "bnk/far-setup",
        "reason": "Provides F5 registry authentication and component versions"
      }
    ],
    "optional": [
      {
        "module": "k8s/cert-manager",
        "reason": "Provides certificate management for FLO webhooks",
        "provides": "Automated certificate management for CRD conversion webhooks"
      }
    ]
  },
  "inputs": {
    "required": [
      {
        "name": "cluster_name",
        "type": "string",
        "description": "Name of the Kubernetes cluster",
        "source": "module",
        "from_module": "infra/aws/eks",
        "from_output": "cluster_name",
        "example": "my-eks-cluster"
      },
      {
        "name": "flo_namespace",
        "type": "string",
        "description": "Namespace for FLO deployment",
        "source": "module",
        "from_module": "bnk/far-setup",
        "from_output": "spk_namespace",
        "example": "f5-spk"
      },
      {
        "name": "flo_version",
        "type": "string",
        "description": "FLO Helm chart version",
        "source": "auto",
        "example": "2.1.0"
      },
      {
        "name": "far_secret_name",
        "type": "string",
        "description": "Name of the FAR registry secret",
        "source": "module",
        "from_module": "bnk/far-setup",
        "from_output": "far_secret_name",
        "example": "far-secret"
      },
      {
        "name": "license_mode",
        "type": "string",
        "description": "FLO licensing mode (connected|disconnected)",
        "source": "user",
        "example": "connected"
      }
    ],
    "optional": [
      {
        "name": "enable_ipam_operator",
        "type": "boolean",
        "description": "Enable F5 IPAM operator for automatic IP assignment",
        "default": false,
        "source": "user"
      },
      {
        "name": "cert_manager_ready",
        "type": "boolean",
        "description": "Dependency flag for cert-manager",
        "default": true,
        "source": "module",
        "from_module": "k8s/cert-manager",
        "from_output": "cert_manager_ready"
      }
    ]
  },
  "outputs": {
    "key_outputs": [
      {
        "name": "flo_ready",
        "type": "boolean",
        "description": "Flag indicating FLO is ready for dependent modules",
        "used_by": [
          "bnk/bnk-gatewayclass",
          "bnk/gateway",
          "bnk/routes",
          "bnk/bnk-secpolicy",
          "bnk/bnk-netpolicy"
        ],
        "sensitive": false
      },
      {
        "name": "flo_namespace",
        "type": "string",
        "description": "Namespace where FLO is deployed",
        "used_by": ["bnk/bnk-gatewayclass"],
        "sensitive": false
      },
      {
        "name": "crds_installed",
        "type": "boolean",
        "description": "Flag indicating CRDs are installed by FLO",
        "used_by": ["bnk/bnk-gatewayclass", "bnk/gateway", "bnk/routes"],
        "sensitive": false
      }
    ]
  },
  "providers": {
    "required": ["kubernetes", "helm"],
    "optional": []
  },
  "backend": {
    "recommendations": {
      "aws": "s3",
      "azure": "azurerm",
      "gcp": "gcs",
      "on-prem": "local"
    }
  },
  "deployment": {
    "order": 50,
    "estimated_time": "3 minutes",
    "requires_user_input": true,
    "sensitive_inputs": ["license_jwt_token"]
  }
}
```

## Input Source Types

### `source: "user"`
User must provide this value. Will appear in variables.tfvars template with example/default.

### `source: "module"`
Value comes from another module's output. Will be auto-wired in root.hcl using `dependency` blocks.

### `source: "auto"`
Value is automatically determined (e.g., from far-setup manifest parsing, data sources, etc.). No user input needed.

## Usage in Code Generation

When generating root.hcl:

1. **Parse module.json** for selected modules
2. **Resolve dependencies** (required + optional user selects)
3. **Build dependency tree** ensuring correct order
4. **Generate terraform blocks** for each module with proper `dependency` references
5. **Generate variables.tfvars** with all `source: "user"` inputs
6. **Generate backend.hcl** based on platform selection

## File Location

Each module should have:
```
module-name/
  ├── main.tf
  ├── variables.tf
  ├── outputs.tf
  ├── versions.tf
  ├── README.md
  └── module.json  ← Metadata file
```
