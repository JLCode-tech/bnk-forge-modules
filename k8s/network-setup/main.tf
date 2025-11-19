# infrastructure-modules/spk-2.1/network-setup/main.tf

resource "kubernetes_manifest" "external_nad" {
  manifest = yamldecode(templatefile("${path.module}/manifests/external-nad.yaml.tftpl", {
    namespace      = var.namespace
    external_cidrs = var.external_subnet_cidrs
  }))

  field_manager {
    name            = "terraform"
    force_conflicts = true
  }
}

resource "kubernetes_manifest" "internal_nad" {
  manifest = yamldecode(templatefile("${path.module}/manifests/internal-nad.yaml.tftpl", {
    namespace      = var.namespace
    internal_cidrs = var.internal_subnet_cidrs
  }))

  field_manager {
    name            = "terraform"
    force_conflicts = true
  }
}