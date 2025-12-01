# infrastructure-modules/spk-2.1/f5-controller/main.tf

# Data source for far-secret
data "kubernetes_secret_v1" "far_secret" {
  metadata {
    name      = var.far_secret_name
    namespace = var.f5_spk_namespace
  }
}

# Render Helm values from template
locals {
  helm_values = templatefile("${path.module}/manifests/values-minimal.yaml.tpl", {
    # Namespaces and registry
    namespace          = var.f5_spk_namespace
    rabbitmq_namespace = var.rabbitmq_namespace
    image_registry     = var.f5_image_registry
    far_secret_name    = var.far_secret_name
    
    # Network attachments
    external_nad_name = var.external_nad_name
    internal_nad_name = var.internal_nad_name
    
    # Service endpoints
    dssm_sentinel_host = var.dssm_sentinel_host
    dssm_sentinel_port = var.dssm_sentinel_port
    
    # TMM resources
    cpu_cores      = var.f5_tmm_cpu_cores
    memory         = var.f5_tmm_memory
    hugepages_2mi  = var.f5_tmm_hugepages_2mi
  })
}

# ========================================================================
# F5 INGRESS CONTROLLER HELM RELEASE
# ========================================================================

resource "helm_release" "f5_controller" {
  name       = "f5ingress"
  repository = "oci://repo.f5.com"
  chart      = "charts/f5ingress"
  version    = var.f5_controller_chart_version
  namespace  = var.f5_spk_namespace
  timeout    = 900
  wait       = false

  depends_on = [
    data.kubernetes_secret_v1.far_secret
  ]

  values = [local.helm_values]
}

# Wait for TMM pods to be running (not Ready, just Running)
resource "time_sleep" "wait_for_tmm" {
  depends_on = [helm_release.f5_controller]
  
  create_duration = "2m"  # Wait 2 minutes for pods to start and grpcSvc to initialize
}


# ========================================================================
# VLAN CUSTOM RESOURCES
# ========================================================================

resource "kubernetes_manifest" "external_vlans" {
  for_each = toset(var.availability_zones)

  depends_on = [time_sleep.wait_for_tmm]

  manifest = {
    apiVersion = "k8s.f5net.com/v1"
    kind       = "F5SPKVlan"
    metadata = {
      name      = "external-vlan-${replace(each.value, "/[^a-z0-9-]/", "-")}"
      namespace = var.f5_spk_namespace
    }
    spec = {
      name         = "external-${replace(each.value, "/[^a-z0-9-]/", "-")}"
      interfaces   = ["1.1"]
      selfip_v4s   = [var.f5_vlan_ips[each.value].external_ip]
      prefixlen_v4 = var.f5_vlan_ips[each.value].external_prefix
      mtu          = var.f5_vlan_mtu
      internal     = false
    }
  }
}

resource "kubernetes_manifest" "internal_vlans" {
  for_each = toset(var.availability_zones)

  depends_on = [time_sleep.wait_for_tmm]

  manifest = {
    apiVersion = "k8s.f5net.com/v1"
    kind       = "F5SPKVlan"
    metadata = {
      name      = "internal-vlan-${replace(each.value, "/[^a-z0-9-]/", "-")}"
      namespace = var.f5_spk_namespace
    }
    spec = {
      name         = "internal-${replace(each.value, "/[^a-z0-9-]/", "-")}"
      interfaces   = ["1.2"]
      internal     = true
      selfip_v4s   = [var.f5_vlan_ips[each.value].internal_ip]
      prefixlen_v4 = var.f5_vlan_ips[each.value].internal_prefix
      mtu          = var.f5_vlan_mtu
    }
  }
}