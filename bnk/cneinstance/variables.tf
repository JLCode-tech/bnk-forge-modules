# bnk/cneinstance/variables.tf
# CNEInstance Module Variables

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
# CLUSTER / INSTANCE
# =============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (auto-wired)"
  type        = string
  default     = ""
}

variable "instance_name" {
  description = "Name of the CNEInstance resource"
  type        = string
  default     = "bnk-instance"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.instance_name))
    error_message = "The instance_name must be a valid Kubernetes resource name (lowercase alphanumeric and hyphens, starting/ending with alphanumeric)."
  }
}

variable "namespace" {
  description = "Namespace for CNEInstance and workloads (wired from bnk-prerequisites.cne_instance_namespace)"
  type        = string
  default     = "f5-bnk"
}

# =============================================================================
# VERSION AND REGISTRY (wired from prerequisites)
# =============================================================================

variable "manifest_version" {
  description = "BNK manifest version (wired from prerequisites.manifest_version)"
  type        = string
  default     = "2.2.1-3.2226.0-0.0.511"
}

variable "far_secret_name" {
  description = "FAR image pull secret name (wired from prerequisites.far_secret_name)"
  type        = string
  default     = "far-secret"
}

# =============================================================================
# NETWORK (wired from network-setup)
# =============================================================================

variable "external_nad_name" {
  description = "External NAD name (wired from network-setup.external_nad_name)"
  type        = string
  default     = "external-netdevice"
}

variable "internal_nad_name" {
  description = "Internal NAD name (wired from network-setup.internal_nad_name)"
  type        = string
  default     = "internal-netdevice"
}

# =============================================================================
# CERTIFICATES (wired from cert-manager)
# =============================================================================

variable "cluster_issuer_name" {
  description = "ClusterIssuer name (wired from cert-manager.cluster_issuer_name)"
  type        = string
  default     = "bnk-ca-cluster-issuer"
}

# =============================================================================
# CLOUD CONFIGURATION (AWS/Azure)
# =============================================================================

variable "cloud_provider" {
  description = "Cloud provider (aws, azure, or empty for generic/on-prem). Enables cloud-aware controller env vars."
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "aws", "azure"], var.cloud_provider)
    error_message = "The cloud_provider value must be one of: \"\" (empty), \"aws\", or \"azure\"."
  }
}

variable "storage_class_name" {
  description = "StorageClass for DSSM PVCs (e.g. gp3 for AWS EBS CSI driver). Empty uses cluster default."
  type        = string
  default     = ""
}

variable "cloud_az_subnet_mappings" {
  description = "AZ-to-subnet mappings for cloud-network-mapping ConfigMap. Required when cloud_provider is set."
  type = list(object({
    az = string
    subnets = list(object({
      cidr      = string
      subnet_id = string
    }))
  }))
  default = []
}

# =============================================================================
# DEPLOYMENT CONFIGURATION
# =============================================================================

variable "deployment_size" {
  description = "Deployment size: Small, Medium, Large, or Max"
  type        = string
  default     = "Small"

  validation {
    condition     = contains(["Small", "Medium", "Large", "Max"], var.deployment_size)
    error_message = "The deployment_size value must be one of: Small, Medium, Large, or Max."
  }
}

variable "whole_cluster" {
  description = "Watch all namespaces for Gateway/Route CRs. With dpu=false, creates a Deployment."
  type        = bool
  default     = true
}

variable "dpu_enabled" {
  description = "Enable DPU (BlueField) mode. Must be explicitly false for AWS/standard k8s."
  type        = bool
  default     = false
}

# =============================================================================
# FEATURE TOGGLES
# These MUST be explicitly set. Empty {} in CRD causes FLO to generate a
# minimal TMM template missing volume mounts and sidecars.
# =============================================================================

variable "dynamic_routing_enabled" {
  description = "Enable dynamic routing (adds tmrouted container to TMM pod)"
  type        = bool
  default     = true
}

variable "firewall_acl_enabled" {
  description = "Enable firewall ACL (adds blobd sidecar + AFM deployment)"
  type        = bool
  default     = true
}

variable "pseudo_cni_enabled" {
  description = "Enable pseudoCNI / CSRC DaemonSet"
  type        = bool
  default     = true
}

variable "core_collection_enabled" {
  description = "Enable core dump collection (DaemonSet per node, uses CPU/PV resources)"
  type        = bool
  default     = false
}

variable "intelligent_lb_enabled" {
  description = "Enable AI Intelligent Load Balancing (deploys f5-analyzer pod for F5BigAnalyzer CRs)"
  type        = bool
  default     = false
}

variable "telemetry_logging_enabled" {
  description = "Enable logging subsystem (fluentbit sidecars)"
  type        = bool
  default     = true
}

variable "telemetry_metrics_enabled" {
  description = "Enable metrics subsystem (observer, OTEL collector, toda-tmstats)"
  type        = bool
  default     = true
}

# =============================================================================
# ENV DISCOVERY
# Disabled by default: checks for OVN annotations (k8s.ovn.org/node-primary-ifaddr)
# which don't exist on AWS VPC CNI, causing false failures on all nodes.
# =============================================================================

variable "env_discovery_enabled" {
  description = "Enable environment discovery (validates SR-IOV, hugepages, node labels)"
  type        = bool
  default     = false
}

variable "env_discovery_stop_on_fail" {
  description = "Halt deployment if envDiscovery finds issues"
  type        = bool
  default     = false
}

# =============================================================================
# TMM ENVIRONMENT VARIABLES
# =============================================================================

variable "tmm_default_mtu" {
  description = "MTU for TMM interfaces (should match your network, e.g. 9000 for jumbo frames)"
  type        = number
  default     = 9000
}

variable "tmm_memory" {
  description = "Memory request/limit for TMM container in sriov mode. In kernel mode, use tmm_resources instead. Default 4Gi matches FLO's Small deployment size baseline."
  type        = string
  default     = "4Gi"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Mi|Ki|G|M|K)?$", var.tmm_memory))
    error_message = "tmm_memory must be a valid Kubernetes memory quantity (e.g., 4Gi, 8192Mi)"
  }
}

variable "tmm_ignore_gateways" {
  description = "Prevent TMM from using eth0 default gateway (required for SR-IOV setups)"
  type        = bool
  default     = true
}

variable "tmm_extra_env" {
  description = "Additional environment variables for TMM container"
  type        = list(object({ name = string, value = string }))
  default     = []
}

# =============================================================================
# TMM DATA-PLANE MODE (kernel | sriov)
# =============================================================================
# In "kernel" mode (default, validated per F5 Doc 3) we add the env vars TMM
# needs to run on the kernel network stack via raw sockets (host-device CNI
# moves the ENI's kernel netdev into the pod). The Multus annotation override
# names the interfaces eth1/eth2 so they match ROBIN_VFIO_RESOURCE_1/2. The
# resources block bumps memory to 6Gi (Small + DPDK assumes 2Gi; kernel mode
# OOMKills at 2Gi).
#
# In "sriov" mode we leave the original DPDK/vfio-pci configuration alone —
# the SR-IOV device plugin allocates the VF and TMM accesses it via vfio.

variable "tmm_data_plane_mode" {
  description = <<-EOT
    TMM data-plane mode. Must match k8s/network-setup.tmm_data_plane_mode.
      "kernel" (default) — host-device CNI + kernel-mode TMM. Adds the 8
        kernel-mode env vars, Multus annotation override (eth1/eth2), and
        bumps memory to 6Gi. Validated per F5 Doc 3 + aws-syd-test.
      "sriov" — legacy DPDK/vfio-pci. No extra env, no resource override.
  EOT
  type        = string
  default     = "kernel"

  validation {
    condition     = contains(["kernel", "sriov"], var.tmm_data_plane_mode)
    error_message = "The tmm_data_plane_mode value must be \"kernel\" or \"sriov\"."
  }
}

variable "external_pci_bus_id" {
  description = "(kernel mode) PCI bus ID of the external ENI. Wire from network-setup.external_pci_bus_id."
  type        = string
  default     = "0000:00:07.0"
}

variable "internal_pci_bus_id" {
  description = "(kernel mode) PCI bus ID of the internal ENI. Wire from network-setup.internal_pci_bus_id."
  type        = string
  default     = "0000:00:08.0"
}

# =============================================================================
# TMM POD RESOURCES + ANNOTATIONS (advanced.tmm.resources / advanced.tmm.annotations)
# =============================================================================
# When tmm_data_plane_mode = "kernel", these defaults are merged in. When set
# explicitly they always win.

variable "tmm_resources" {
  description = <<-EOT
    Resource requests/limits for the TMM container, merged into
    advanced.tmm.resources. In kernel mode the operator-default 2Gi from
    deploymentSize=Small triggers OOMKill; we override to 6Gi. CPU + hugepages
    keep the operator defaults. Set explicitly to override (e.g.
    {requests = {memory = "8Gi", cpu = "4"}, limits = {memory = "8Gi", cpu = "4"}}).
    Pass null (default) to use the kernel-mode default (6Gi memory) or operator
    defaults in sriov mode.
  EOT
  type = object({
    requests = map(string)
    limits   = map(string)
  })
  default = null
}

variable "tmm_pod_annotations" {
  description = <<-EOT
    Annotations to apply to the TMM pod template (advanced.tmm.annotations).
    In kernel mode this includes the Multus k8s.v1.cni.cncf.io/networks
    override that names the interfaces eth1 and eth2 so they match
    ROBIN_VFIO_RESOURCE_1 and ROBIN_VFIO_RESOURCE_2.
  EOT
  type        = map(string)
  default     = {}
}

# =============================================================================
# tmm-init ConfigMap (Doc 3 page 28-29)
# =============================================================================
# TMM auto-mounts a ConfigMap named "tmm-init" from its own namespace at
# /opt/lib/tmm/. The CM contains 3 keys:
#   static_conf.tcl  — TMM static config (kept empty by default)
#   tmm_init.tcl     — TMM init TCL: profiles, pools, file_reload directive
#   user_conf.tcl    — site-specific TCL: per-node gateway switch + static
#                      routes. Reloaded every 1s by the file_reload directive.
#
# Why this matters: the TMM pod's only default route is via the internal
# control-plane interface (`tmm` 169.254.0.254). Kernel ICMP/TCP responses
# to a same-VPC client (e.g. a jumphost) leak via that interface and never
# reach the client. Adding `route 10.0.1.0/24 gw 10.0.11.1` (or whatever
# matches your client subnet + external gateway) sends responses out via
# eth1 instead. This is the missing piece for VIP-from-same-VPC to work.

variable "tmm_init_enabled" {
  description = "Create the tmm-init ConfigMap. Required for kernel-mode TMM to route traffic back to clients on subnets other than the data-plane subnets. Default false to preserve backward compat; set true on AWS kernel-mode deployments."
  type        = bool
  default     = false
}

variable "tmm_init_routes" {
  description = <<-EOT
    Static routes added to TMM via tmm-init/user_conf.tcl. Each route maps
    a destination CIDR to a gateway. Example for aws-syd-test (jumphost in
    10.0.1.0/24, external gateway 10.0.11.1):
      [{ destination = "10.0.1.0/24", gateway = "10.0.11.1", description = "jumphost / client subnet via external" }]
    For multi-AZ TGW deployments use tmm_init_user_conf_tcl_raw to provide
    the full per-node switch + GRE endpoints (Doc 3 page 28-29 pattern).
  EOT
  type = list(object({
    destination = string # e.g. "10.0.1.0/24" or "10.0.17.25/32"
    gateway     = string # e.g. "10.0.11.1"
    description = string # short comment, emitted as TCL comment
  }))
  default = []
}

variable "tmm_init_user_conf_tcl_raw" {
  description = <<-EOT
    Optional raw TCL for /opt/lib/tmm/user_conf.tcl. Wins over
    tmm_init_routes if set (use for multi-AZ TGW per-node switch + GRE
    endpoints). The file is reloaded every 1s by tmm_init.tcl's file_reload
    directive, so updates propagate without a TMM restart.
  EOT
  type        = string
  default     = ""
}

variable "tmm_init_extra_tcl" {
  description = <<-EOT
    Optional extra TCL appended to tmm_init.tcl after the default boilerplate
    (set_from_env POD_IP + file_reload directive). Use for application-specific
    profiles (Diameter, GTP, HTTP), pools, snatpools, or bigdb tweaks. See Doc 3
    page 27 for examples.
  EOT
  type        = string
  default     = ""
}

variable "controller_extra_env" {
  description = "Additional environment variables for CNE controller"
  type        = list(object({ name = string, value = string }))
  default     = []
}

# =============================================================================
# DEPENDENCY GATES
# =============================================================================

variable "flo_ready" {
  description = "Gate from FLO module — ensures FLO is deployed and CRDs exist"
  type        = bool
  default     = true
}
