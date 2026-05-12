# k8s/bnk-prerequisites/main.tf
# BNK Prerequisites — Namespaces + FAR Secrets + Manifest Download
#
# This module is the FIRST module in the BNK stack. It:
# 1. Creates required namespaces (f5-operator, f5-utils, gateway-ns)
# 2. Creates FAR image pull secrets from cne_pull_secret (project secret)
# 3. Downloads BNK manifest from repo.f5.com
# 4. Parses component versions (FLO version, cert-manager version, etc.)
#
# The cne_pull_secret is the base64-encoded JSON service account key from F5.
# It is injected as a project secret (highest priority in variable resolution).

# =============================================================================
# KUBECONFIG FOR KUBECTL (used by destroy-time cleanup)
# =============================================================================
# Platform-agnostic kubeconfig for kubectl in local-exec provisioners.
# local.forge_kubeconfig is injected by BNK-Forge via bnk_forge_providers.tf.
# Falls back to var.forge_kubeconfig_content for standalone usage outside Forge.

resource "local_file" "kubeconfig" {
  filename        = "${path.module}/work/kubeconfig"
  file_permission = "0600"
  content         = try(local.forge_kubeconfig, var.forge_kubeconfig_content)
}

# =============================================================================
# LOCALS
# =============================================================================

locals {
  kubectl = "kubectl --kubeconfig ${local_file.kubeconfig.filename}"

  # ---------------------------------------------------------------------------
  # FAR Docker Auth — handles BOTH credential formats
  # ---------------------------------------------------------------------------
  # The cne_pull_secret project secret can be provided in two formats:
  #
  # Format A (bare service account key):
  #   var.cne_pull_secret is the base64-encoded JSON service account key from F5.
  #   → We construct dockerconfigjson with _json_key_base64:<base64-key> auth.
  #
  # Format B (pre-built dockerconfigjson):
  #   var.cne_pull_secret is a base64-encoded dockerconfigjson that already
  #   contains {"auths":{"repo.f5.com":{"auth":"..."}}}
  #   → We extract the raw JSON key from the inner auth and rebuild correctly.
  #
  # Detection: base64-decode the value; if it parses as JSON with an "auths"
  # key, it's Format B. Otherwise, it's Format A.
  #
  # IMPORTANT — F5 FLO auth format (per F5 docs):
  #   auth = base64("_json_key_base64:" + base64(raw_json_key))
  # The "_json_key_base64" prefix tells FLO the password is base64-encoded.
  # The password MUST be base64(json), NOT raw json.
  # ---------------------------------------------------------------------------

  # Try to base64-decode and parse as JSON to detect format
  _decoded_secret = try(base64decode(var.cne_pull_secret), "")
  _is_dockerconfig = try(
    lookup(jsondecode(local._decoded_secret), "auths", null) != null,
    false
  )

  # ---------------------------------------------------------------------------
  # Format B: extract the raw JSON key from the pre-built dockerconfigjson.
  # The inner auth decodes to "username:password" where password is the raw
  # JSON key (possibly pretty-printed with newlines).
  # ---------------------------------------------------------------------------
  _format_b_decoded_auth = local._is_dockerconfig ? try(
    base64decode(jsondecode(local._decoded_secret)["auths"]["repo.f5.com"]["auth"]),
    ""
  ) : ""

  # Extract the password portion (everything after first ":")
  # e.g. "_json_key:{...json...}" → "{...json...}"
  _format_b_raw_key = local._is_dockerconfig && local._format_b_decoded_auth != "" ? (
    length(regexall(":", local._format_b_decoded_auth)) > 0
    ? join(":", slice(split(":", local._format_b_decoded_auth), 1, length(split(":", local._format_b_decoded_auth))))
    : local._format_b_decoded_auth
  ) : ""

  # ---------------------------------------------------------------------------
  # Build the correct dockerconfigjson for both formats.
  #
  # Per F5 docs (create-far-namespace.html):
  #   auth = base64("_json_key_base64:" + raw_content_of_sa_key_file)
  # where the SA key file content is ALREADY base64-encoded.
  #
  # Format A: var.cne_pull_secret IS the base64-encoded SA key → use directly.
  # Format B: we extracted raw JSON key → base64-encode it first.
  # ---------------------------------------------------------------------------
  docker_config_json = local._is_dockerconfig ? jsonencode({
    auths = {
      "repo.f5.com" = {
        auth = base64encode("_json_key_base64:${base64encode(local._format_b_raw_key)}")
      }
    }
    }) : jsonencode({
    auths = {
      "repo.f5.com" = {
        auth = base64encode("_json_key_base64:${var.cne_pull_secret}")
      }
    }
  })
}

# =============================================================================
# DESTROY-TIME CLEANUP
# =============================================================================
# BNK installs webhooks and CRD instances with finalizers. On destroy:
# 1. Delete F5 validating/mutating webhooks (they block resource deletion)
# 2. Strip finalizers from all F5 CRD instances (they block namespace deletion)
# 3. Strip finalizers from F5SPKVlan CRs (handletmmconfig_inconsistency)
# 4. Force-finalize namespace if still stuck
#
# Without this, namespace deletion hangs indefinitely because:
# - Webhook f5validate.f5net.com tries to call a service that's already deleted
# - CNEInstance has k8s.f5.com/CNEInstanceFinalizer
# - FLO component CRs have k8s.f5net.com/uninstall finalizer
# - VLAN CRs have handletmmconfig_inconsistency finalizer

resource "null_resource" "bnk_cleanup" {
  triggers = {
    operator_namespace = var.operator_namespace
    utils_namespace    = var.utils_namespace
    instance_namespace = var.instance_namespace
    kubeconfig         = local_file.kubeconfig.filename
  }

  # Create: no-op
  provisioner "local-exec" {
    command = "echo 'BNK cleanup resource created (runs on destroy only)'"
  }

  # Destroy: clean up webhooks, finalizers, and stuck namespaces
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      KUBECONFIG="${self.triggers.kubeconfig}"
      NS="${self.triggers.operator_namespace}"
      KC="kubectl --kubeconfig $KUBECONFIG"

      echo "=== BNK Pre-Destroy Cleanup ==="

      # Step 1: Delete F5 webhooks
      echo "Step 1: Removing F5 webhooks..."
      for wh in $($KC get validatingwebhookconfiguration -o name 2>/dev/null | grep f5); do
        echo "  Deleting $wh"
        $KC delete $wh --timeout=10s 2>/dev/null || true
      done
      for wh in $($KC get mutatingwebhookconfiguration -o name 2>/dev/null | grep f5); do
        echo "  Deleting $wh"
        $KC delete $wh --timeout=10s 2>/dev/null || true
      done

      # Step 2: Strip finalizers from all F5 CRD instances in namespace
      echo "Step 2: Stripping finalizers from F5 CRD instances..."
      F5_CRDS=$($KC get crd -o name 2>/dev/null | grep -E 'k8s\.f5\.(com|net\.com)' | sed 's|customresourcedefinition.apiextensions.k8s.io/||')
      for crd in $F5_CRDS; do
        RESOURCES=$($KC get $crd -n $NS -o name 2>/dev/null)
        for res in $RESOURCES; do
          echo "  Patching $res"
          $KC patch $res -n $NS --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
        done
      done

      # Step 3: Also check utils namespace
      F5_UTILS_NS="${self.triggers.utils_namespace}"
      for crd in $F5_CRDS; do
        RESOURCES=$($KC get $crd -n $F5_UTILS_NS -o name 2>/dev/null)
        for res in $RESOURCES; do
          echo "  Patching $res (in $F5_UTILS_NS)"
          $KC patch $res -n $F5_UTILS_NS --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
        done
      done

      # Step 3b: Also check instance namespace (DPU mode)
      INSTANCE_NS="${self.triggers.instance_namespace}"
      if [ -n "$INSTANCE_NS" ] && [ "$INSTANCE_NS" != "$NS" ] && [ "$INSTANCE_NS" != "$F5_UTILS_NS" ]; then
        for crd in $F5_CRDS; do
          RESOURCES=$($KC get $crd -n $INSTANCE_NS -o name 2>/dev/null)
          for res in $RESOURCES; do
            echo "  Patching $res (in $INSTANCE_NS)"
            $KC patch $res -n $INSTANCE_NS --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
          done
        done
      fi

      # Step 4: Delete all F5 CRDs (cluster-scoped)
      # FLO's crd-installer expects to create these fresh. Stale CRDs from a
      # previous deploy cause conflicts and failed reconciliation.
      echo "Step 4: Deleting F5 CRDs..."
      for crd in $F5_CRDS; do
        echo "  Deleting CRD $crd"
        $KC delete crd $crd --timeout=30s 2>/dev/null || true
      done
      # Also catch any with fic.f5.com (IPAM CRDs)
      for crd in $($KC get crd -o name 2>/dev/null | grep 'fic\.f5\.com' | sed 's|customresourcedefinition.apiextensions.k8s.io/||'); do
        echo "  Deleting CRD $crd"
        $KC delete crd $crd --timeout=30s 2>/dev/null || true
      done

      echo "=== BNK cleanup complete ==="
    EOT
  }

  depends_on = [
    kubernetes_namespace_v1.operator,
    kubernetes_namespace_v1.utils,
    kubernetes_namespace_v1.gateway,
    kubernetes_namespace_v1.instance,
  ]
}

# =============================================================================
# NAMESPACES
# =============================================================================

resource "kubernetes_namespace_v1" "operator" {
  metadata {
    name = var.operator_namespace
    labels = {
      "app.kubernetes.io/name"       = "f5-operator"
      "app.kubernetes.io/component"  = "bnk-operators"
      "app.kubernetes.io/managed-by" = "terraform"
      "f5.com/product"               = "bnk"
    }
    annotations = {
      "description" = "F5 BNK control plane + all components deployed by FLO via CNEInstance"
    }
  }
}

resource "kubernetes_namespace_v1" "utils" {
  metadata {
    name = var.utils_namespace
    labels = {
      "app.kubernetes.io/name"       = "f5-utils"
      "app.kubernetes.io/component"  = "bnk-utilities"
      "app.kubernetes.io/managed-by" = "terraform"
      "f5.com/product"               = "bnk"
    }
    annotations = {
      "description" = "F5 BNK utility components (IPAM if deployed separately)"
    }
  }
}

resource "kubernetes_namespace_v1" "gateway" {
  metadata {
    name = var.gateway_namespace
    labels = {
      "app.kubernetes.io/name"       = var.gateway_namespace
      "app.kubernetes.io/component"  = "gateway-api"
      "app.kubernetes.io/managed-by" = "terraform"
      "f5.com/product"               = "bnk"
    }
    annotations = {
      "description" = "Namespace for Gateway API resources (Gateway, HTTPRoute, etc.)"
    }
  }
}

# =============================================================================
# FAR IMAGE PULL SECRETS
# =============================================================================
# Create far-secret in every namespace. FLO + CNEInstance + CRD installer all
# need to pull images from repo.f5.com.

resource "kubernetes_secret_v1" "far_secret_operator" {
  metadata {
    name      = "far-secret"
    namespace = kubernetes_namespace_v1.operator.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "far-auth"
      "app.kubernetes.io/managed-by" = "terraform"
      "f5.com/product"               = "bnk"
    }
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = local.docker_config_json
  }
}

resource "kubernetes_secret_v1" "far_secret_utils" {
  metadata {
    name      = "far-secret"
    namespace = kubernetes_namespace_v1.utils.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "far-auth"
      "app.kubernetes.io/managed-by" = "terraform"
      "f5.com/product"               = "bnk"
    }
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = local.docker_config_json
  }
}

resource "kubernetes_secret_v1" "far_secret_gateway" {
  metadata {
    name      = "far-secret"
    namespace = kubernetes_namespace_v1.gateway.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "far-auth"
      "app.kubernetes.io/managed-by" = "terraform"
      "f5.com/product"               = "bnk"
    }
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = local.docker_config_json
  }
}

# =============================================================================
# INSTANCE NAMESPACE (DPU mode — f5-bnk)
# =============================================================================
# When instance_namespace is set and differs from operator_namespace, FLO
# deploys BNK components there and needs a far-secret for image pulls.

resource "kubernetes_namespace_v1" "instance" {
  count = var.instance_namespace != "" && var.instance_namespace != var.operator_namespace ? 1 : 0

  metadata {
    name = var.instance_namespace
    labels = {
      "app.kubernetes.io/name"       = var.instance_namespace
      "app.kubernetes.io/component"  = "bnk-instance"
      "app.kubernetes.io/managed-by" = "terraform"
      "f5.com/product"               = "bnk"
    }
    annotations = {
      "description" = "F5 BNK instance namespace (CNEInstance + all BNK components)"
    }
  }
}

resource "kubernetes_secret_v1" "far_secret_instance" {
  count = var.instance_namespace != "" && var.instance_namespace != var.operator_namespace ? 1 : 0

  metadata {
    name      = "far-secret"
    namespace = kubernetes_namespace_v1.instance[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "far-auth"
      "app.kubernetes.io/managed-by" = "terraform"
      "f5.com/product"               = "bnk"
    }
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = local.docker_config_json
  }
}

# =============================================================================
# WRITE SERVICE ACCOUNT KEY TO TEMP FILE (for helm registry login)
# =============================================================================
# The scripts need a file path for `helm registry login`. We write the
# cne_pull_secret content to a temp file in the module workspace.

resource "local_sensitive_file" "service_account_key" {
  filename = "${path.module}/work/cne_pull_secret.json"
  content  = var.cne_pull_secret
}

# =============================================================================
# MANIFEST DOWNLOAD AND VERSION PARSING
# =============================================================================
# Downloads the BNK manifest chart from repo.f5.com using helm CLI.
# Parses out all component versions (FLO, cert-manager, CWC, etc.)

data "external" "manifest_download" {
  program = ["bash", "${path.module}/scripts/download-manifest.sh"]

  query = {
    manifest_version         = var.bnk_manifest_version
    chart_name               = "f5-bigip-k8s-manifest"
    work_dir                 = "${path.module}/work"
    service_account_key_file = local_sensitive_file.service_account_key.filename
  }

  depends_on = [local_sensitive_file.service_account_key]
}

data "external" "component_versions" {
  program = ["bash", "${path.module}/scripts/parse-versions.sh"]

  query = {
    manifest_file = data.external.manifest_download.result.manifest_file
  }

  depends_on = [data.external.manifest_download]
}
