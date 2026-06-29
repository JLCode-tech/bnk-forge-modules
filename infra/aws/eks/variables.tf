# infrastructure-modules/foundation/eks/variables.tf

# =============================================================================
# PROJECT VARIABLES (must match security module exactly)
# =============================================================================

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_profile" {
  description = "AWS profile for authentication"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# SECURITY CONFIGURATION (must match security module exactly)
# =============================================================================

variable "user_ip" {
  description = "Your public IP address in CIDR format (e.g., 203.123.45.67/32) for EKS API endpoint access"
  type        = string

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}/32$", var.user_ip))
    error_message = "The user_ip must be in CIDR format with /32 suffix (e.g., 203.123.45.67/32)."
  }
}

# =============================================================================
# VPC DEPENDENCY VARIABLES (from VPC module outputs)
# =============================================================================

variable "vpc_id" {
  description = "ID of the VPC where resources will be created"
  type        = string
}

variable "private_external_subnet_ids" {
  description = "IDs of the private external subnets for EKS nodes"
  type        = list(string)
}

variable "private_internal_subnet_ids" {
  description = "IDs of the private internal subnets for EKS nodes"
  type        = list(string)
}

# =============================================================================
# SECURITY DEPENDENCY VARIABLES (from Security module outputs)
# =============================================================================

variable "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster service role"
  type        = string
}

variable "nodegroup_role_arn" {
  description = "ARN of the EKS nodegroup role"
  type        = string
}

variable "vpc_security_group_id" {
  description = "ID of the VPC security group"
  type        = string
}

variable "infrastructure_key_name" {
  description = "Name of the EC2 key pair for node access"
  type        = string
}

# =============================================================================
# EKS SPECIFIC CONFIGURATION
# =============================================================================

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"
}

variable "instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "m5.xlarge"
}

variable "node_count" {
  description = "Number of worker nodes in the EKS node group"
  type        = number
  default     = 2
}

# =============================================================================
# FEATURE TOGGLES
# =============================================================================

variable "enable_efs_csi_driver" {
  description = "Enable EFS CSI driver addon"
  type        = bool
  default     = true
}

variable "enable_snapshot_controller" {
  description = "Enable snapshot controller addon"
  type        = bool
  default     = true
}

# =============================================================================
# CSI DRIVER ADDON VERSIONS
# =============================================================================

variable "ebs_csi_addon_version" {
  description = "Version of the EBS CSI driver addon"
  type        = string
  default     = "v1.35.0-eksbuild.1"
}

variable "efs_csi_addon_version" {
  description = "Version of the EFS CSI driver addon"
  type        = string
  default     = "v2.1.0-eksbuild.1"
}

variable "snapshot_controller_addon_version" {
  description = "Version of the snapshot controller addon"
  type        = string
  default     = "v8.1.0-eksbuild.1"
}