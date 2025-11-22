# infrastructure-modules/spk-2.1/bnk-netpolicy/versions.tf

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }

    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.2"
    }
  }
}
