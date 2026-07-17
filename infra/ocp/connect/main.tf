# infra/ocp/connect/main.tf
# Validates connectivity to an existing OpenShift cluster

locals {
  # Precedence: forge-injected kubeconfig (registered cluster) > manual
  # var.kubeconfig_content (standalone/override) > token-based fallback.
  # local.forge_kubeconfig is injected by BNK-Forge via bnk_forge_locals.tf
  # whenever this workspace has a registered cluster; try() falls through
  # to the next tier when forge hasn't injected it (e.g. standalone runs).
  kubeconfig = try(local.forge_kubeconfig, var.kubeconfig_content != "" ? var.kubeconfig_content : yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{ name = "ocp", cluster = {
      server                   = var.api_server_url
      insecure-skip-tls-verify = var.skip_tls_verify
    } }]
    users           = [{ name = "ocp-user", user = { token = var.oc_token } }]
    contexts        = [{ name = "default", context = { cluster = "ocp", user = "ocp-user" } }]
    current-context = "default"
  }))
}

resource "local_file" "kubeconfig" {
  filename        = "${path.module}/work/kubeconfig"
  file_permission = "0600"
  content         = local.kubeconfig
}

resource "null_resource" "validate_connectivity" {
  depends_on = [local_file.kubeconfig]

  provisioner "local-exec" {
    command = "kubectl --kubeconfig ${local_file.kubeconfig.filename} cluster-info"
  }
}
