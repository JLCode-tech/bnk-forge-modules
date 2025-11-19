# Example usage for k8s/cert-manager module

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "git::https://github.com/JLCode-tech/bnk-forge-modules.git//k8s/cert-manager?ref=v1.0.0"
}

inputs = {
  # Add required inputs here
  # See ../variables.tf for all available options
}
