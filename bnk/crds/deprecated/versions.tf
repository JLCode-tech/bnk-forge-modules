# infrastructure-modules/spk-2.1/crds/deprecated/versions.tf

terraform {
  required_version = ">= 1.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}