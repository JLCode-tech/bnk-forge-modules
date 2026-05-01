# bnk/bnk-vlans/variables.tf
# F5SPKVlan Module Variables

# =============================================================================
# PLATFORM KUBECONFIG (injected by BNK-Forge or set manually)
# =============================================================================

variable "forge_kubeconfig_content" {
  description = "Kubeconfig YAML content. Automatically injected by BNK-Forge for any platform (EKS, AKS, GKE, OCP, generic). Set manually for standalone usage."
  type        = string
  default     = ""
  sensitive   = true
}

# =============================================================================
# CLUSTER
# =============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (auto-wired)"
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Namespace for VLAN CRs (must match CNEInstance namespace)"
  type        = string
  default     = "f5-bnk"
}

# =============================================================================
# SELF IPS — static IPs that TMM will configure on its data-plane interfaces
# These are chosen by the operator from the subnet range.
# One IP per TMM replica. NADs have NO IPAM — TMM sets these IPs itself
# via the F5SPKVlan CR.
# =============================================================================

variable "external_self_ips" {
  description = "External self IPs for TMM VLANs (one per TMM replica, from external subnet). If empty, auto-derived as .240 from first external subnet CIDR."
  type        = list(string)
  default     = []
}

variable "internal_self_ips" {
  description = "Internal self IPs for TMM VLANs (one per TMM replica, from internal subnet). If empty, auto-derived as .240 from first internal subnet CIDR."
  type        = list(string)
  default     = []
}

# =============================================================================
# SUBNET CIDRS — needed to derive prefix length
# =============================================================================

variable "external_subnet_cidrs" {
  description = "External subnet CIDRs (used to derive prefix length for VLAN CR)"
  type        = list(string)
  default     = ["10.0.10.0/24"]
}

variable "internal_subnet_cidrs" {
  description = "Internal subnet CIDRs (used to derive prefix length for VLAN CR)"
  type        = list(string)
  default     = ["10.0.20.0/24"]
}

# =============================================================================
# MTU
# =============================================================================

variable "mtu" {
  description = "MTU for VLAN interfaces (should match TMM_DEFAULT_MTU)"
  type        = number
  default     = 9000
}

# =============================================================================
# AWS ENI SECONDARY IP REGISTRATION
# Set aws_region to enable automatic ENI discovery and secondary IP registration.
# This is required on AWS because the Nitro hypervisor ARP proxy blackholes
# traffic to unregistered IPs.
# =============================================================================

variable "aws_region" {
  description = "AWS region for ENI operations. Empty string disables ENI registration (for on-prem/DPU)."
  type        = string
  default     = ""
}

variable "gateway_vips" {
  description = "Gateway VIP addresses to register on the external ENI (in addition to self-IPs)"
  type        = list(string)
  default     = []
}

variable "internal_subnet_id" {
  description = "Internal subnet ID — used to discover the internal ENI on the HP node"
  type        = string
  default     = ""
}

# =============================================================================
# ROUTING
# =============================================================================

variable "auto_lasthop" {
  description = "Auto last-hop setting for VLANs. Set to AUTO_LASTHOP_ENABLED on cloud (AWS/Azure) to prevent asymmetric routing."
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "AUTO_LASTHOP_ENABLED", "AUTO_LASTHOP_DISABLED", "AUTO_LASTHOP_DEFAULT"], var.auto_lasthop)
    error_message = "auto_lasthop must be one of: '' (empty/omit), 'AUTO_LASTHOP_ENABLED', 'AUTO_LASTHOP_DISABLED', 'AUTO_LASTHOP_DEFAULT'"
  }
}

# =============================================================================
# DEPENDENCY GATES
# =============================================================================

variable "flo_ready" {
  description = "Gate from FLO module — ensures FLO is running and will install CRDs"
  type        = bool
  default     = true
}
