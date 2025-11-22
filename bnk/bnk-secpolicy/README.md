# BNKSecPolicy Module

## Overview

Creates security policies for BIG-IP Next Gateways including firewall rules, DDoS protection, access control, rate limiting, and security logging.

## Features

- Firewall policy integration (F5BigFwPolicy)
- DDoS protection (F5BigDdosGlobal)
- IP-based access control (allow/deny lists)
- Rate limiting
- Security event logging
- Address list references

## Dependencies

- **FLO**: For BNKSecPolicy CRD

## Usage

```hcl
module "security_policy" {
  source = "./bnk/bnk-secpolicy"

  cluster_name      = "my-eks-cluster"
  policy_name       = "gateway-security"
  policy_namespace  = "default"

  # Firewall
  enable_firewall = true
  firewall_policy_ref = {
    name = "default-firewall-policy"
  }

  # DDoS protection
  enable_ddos = true
  ddos_protection_mode = "auto"

  # Access control
  allowed_source_ranges = [
    "10.0.0.0/8",
    "192.168.0.0/16"
  ]

  # Rate limiting
  enable_rate_limiting = true
  rate_limit_config = {
    requests_per_second = 1000
    burst_size          = 2000
    key                 = "remote_address"
  }

  # Logging
  log_profile_ref = {
    name = "security-log-profile"
  }

  flo_ready = module.flo.flo_ready

  common_labels = {
    environment = "production"
  }
}
```

## Attach to Gateway

Policies are attached to Gateways via the Gateway module:

```hcl
module "gateway" {
  source = "./bnk/gateway"

  security_policy_refs = [
    {
      name = module.security_policy.policy_name
    }
  ]
}
```

## Module Metadata

- **Category**: bnk
- **Workflow Compatibility**: Greenfield, Partial
- **Version**: 2.1.x
- **Last Updated**: 2025-11-22
