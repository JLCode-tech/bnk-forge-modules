# k8s/network-setup/variables.tf
# Network Setup Module Variables

# =============================================================================
# CLUSTER / NAMESPACE
# =============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (auto-wired)"
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Namespace for NADs — must match CNEInstance namespace"
  type        = string
  default     = "f5-bnk"
}

# =============================================================================
# CNI CONFIGURATION
# =============================================================================
#
# Default mode: host-device + pciBusID. The host-device CNI moves a kernel
# network interface from the host's netns into the TMM pod's netns. Identifying
# the device by PCI bus ID is deterministic across boots and AMI udev rules
# (the kernel ifname can be eth1/ens7/etc. depending on the AMI). Matches Doc 3
# (AWS Cloud Multi-AZ Network Architecture) and the validated aws-syd-test
# blueprint.
#
# Set tmm_data_plane_mode = "sriov" only for legacy DPDK/vfio-pci deployments
# (e.g. on-prem telco). In sriov mode the NAD uses an SR-IOV resourceName
# annotation so the SR-IOV device plugin allocates the VF.

variable "tmm_data_plane_mode" {
  description = <<-EOT
    TMM data-plane mode:
      "kernel" (default) — host-device CNI moves the ENI's kernel netdev into
        the TMM pod. TMM uses TMM_GENERIC_SOCKET_DRIVER=true. Validated on AWS
        per F5 Doc 3 (Multi-AZ Network Architecture).
      "sriov" — legacy DPDK/vfio-pci binding via SR-IOV device plugin. Requires
        the high-performance-nodes module to provision the SR-IOV stack.
  EOT
  type        = string
  default     = "kernel"

  validation {
    condition     = contains(["kernel", "sriov"], var.tmm_data_plane_mode)
    error_message = "The tmm_data_plane_mode value must be \"kernel\" or \"sriov\"."
  }
}

variable "external_pci_bus_id" {
  description = <<-EOT
    PCI bus ID of the external SR-IOV ENI (e.g. "0000:00:07.0"). Required when
    tmm_data_plane_mode = "kernel". The high-performance-nodes module attaches
    a dedicated external ENI at this PCI slot.
  EOT
  type        = string
  default     = "0000:00:07.0"
}

variable "internal_pci_bus_id" {
  description = <<-EOT
    PCI bus ID of the internal SR-IOV ENI (e.g. "0000:00:08.0"). Required when
    tmm_data_plane_mode = "kernel". The high-performance-nodes module attaches
    a dedicated internal ENI at this PCI slot.
  EOT
  type        = string
  default     = "0000:00:08.0"
}

# =============================================================================
# LEGACY SR-IOV CNI CONFIGURATION
# Used only when tmm_data_plane_mode = "sriov".
# =============================================================================

variable "cni_type" {
  description = "CNI plugin type — \"host-device\" (kernel mode, default) or \"sriov\"/\"vfio\" (legacy)"
  type        = string
  default     = "host-device"
}

variable "external_resource_name" {
  description = "(sriov mode only) SR-IOV device plugin resource name for external network"
  type        = string
  default     = "intel.com/external_netdevice"
}

variable "internal_resource_name" {
  description = "(sriov mode only) SR-IOV device plugin resource name for internal network"
  type        = string
  default     = "intel.com/internal_netdevice"
}
