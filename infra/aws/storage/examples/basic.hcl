# Example usage for infra/aws/storage module

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "git::https://github.com/JLCode-tech/bnk-forge-modules.git//infra/aws/storage?ref=v1.0.0"
}

inputs = {
  # Add required inputs here
  # See ../variables.tf for all available options
}
