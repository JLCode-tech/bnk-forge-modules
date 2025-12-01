# infrastructure-modules/spk-2.1/far-setup/main.tf

# =============================================================================
# LOCAL VARIABLES
# =============================================================================

locals {
  # Create list of all namespaces that need FAR secrets
  far_namespaces = [
    var.spk_namespace,
    var.utils_namespace
  ]
  
  # Service account key content
  service_account_key = file(var.service_account_key_file)
  
  # Base64 encoded authentication for docker config
  docker_auth = base64encode("_json_key_base64:${local.service_account_key}")
}

# =============================================================================
# EKS CLUSTER DATA SOURCES
# =============================================================================

# Data source to get cluster info
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# =============================================================================
# KUBERNETES NAMESPACES
# =============================================================================

# Create SPK namespace for controller/TMM
resource "kubernetes_namespace" "spk" {
  metadata {
    name = var.spk_namespace
    labels = {
      "app.kubernetes.io/name"       = "spk"
      "app.kubernetes.io/component"  = "controller"
      "app.kubernetes.io/managed-by" = "terraform"
      "f5.com/spk-version"          = var.spk_manifest_version
    }
  }
}

# Create utils namespace for shared components  
resource "kubernetes_namespace" "utils" {
  metadata {
    name = var.utils_namespace
    labels = {
      "app.kubernetes.io/name"       = "spk"
      "app.kubernetes.io/component"  = "utils"
      "app.kubernetes.io/managed-by" = "terraform" 
      "f5.com/spk-version"          = var.spk_manifest_version
    }
  }
}

# =============================================================================
# FAR AUTHENTICATION SECRETS
# =============================================================================

# Create FAR authentication secrets in each namespace
resource "kubernetes_secret" "far_auth" {
  for_each = toset(local.far_namespaces)

  metadata {
    name      = "far-secret"
    namespace = each.value
    labels = {
      "app.kubernetes.io/name"       = "spk"
      "app.kubernetes.io/component"  = "far-auth"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "repo.f5.com" = {
          auth = local.docker_auth
        }
      }
    })
  }

  depends_on = [
    kubernetes_namespace.spk,
    kubernetes_namespace.utils
  ]
}

# =============================================================================
# MANIFEST FILE DOWNLOAD AND PARSING
# =============================================================================

# Download and extract manifest file
data "external" "manifest_download" {
  program = ["bash", "${path.module}/scripts/download-manifest.sh"]

  query = {
    manifest_version = var.spk_manifest_version
    chart_name = var.manifest_chart_name
    work_dir         = "${path.module}/work"
  }
}

# Parse component versions from manifest
data "external" "component_versions" {
  program = ["bash", "${path.module}/scripts/parse-versions.sh"]

  query = {
    manifest_file = data.external.manifest_download.result.manifest_file
  }

  depends_on = [data.external.manifest_download]
}

# =============================================================================
# VALIDATION
# =============================================================================

# Validate that required component versions were parsed
# Note: CWC, CRDs, F5Ingress, DSSM, Fluentd are now managed by FLO (F5 Lifecycle Operator)
# FAR-setup only needs to validate prerequisites: cert_manager and flo
resource "local_file" "version_validation" {
  filename = "${path.module}/work/versions-validated.json"
  content = jsonencode({
    validation_timestamp = timestamp()
    required_components = [
      "cert_manager",
      "flo"
    ]
    parsed_versions = data.external.component_versions.result
    validation_passed = alltrue([
      for component in ["cert_manager", "flo"] :
      lookup(data.external.component_versions.result, component, "") != ""
    ])
    note = "FLO manages: CWC, DSSM, Fluentd, F5Ingress, CRDs (common, service-proxy, deprecated)"
  })

  depends_on = [data.external.component_versions]
}