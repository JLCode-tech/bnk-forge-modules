# bnk/cneinstance/main.tf
# CNEInstance — BIG-IP Next for Kubernetes GA 2.2
#
# Creates the CNEInstance custom resource which tells FLO to deploy
# ALL BNK components (TMM, CWC, DSSM, Observer, OTEL, RabbitMQ, etc.)
# into the instance namespace.
#
# Uses kubectl apply (not kubernetes_manifest) because:
# - The CNEInstance CRD is installed by FLO, not available at plan time
# - kubernetes_manifest requires CRD at plan time
# - kubectl is available in the celery-worker container
# - Platform-agnostic: kubectl uses Forge-injected kubeconfig

# =============================================================================
# KUBECONFIG FOR KUBECTL
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
# LOCAL VALUES
# =============================================================================

locals {
  kubectl = "kubectl --kubeconfig ${local_file.kubeconfig.filename}"

  is_kernel_mode = var.tmm_data_plane_mode == "kernel"

  # Kernel-mode TMM env vars — added when tmm_data_plane_mode = "kernel".
  # Per F5 Doc 3 (Multi-AZ Network Architecture) advanced.tmm.env, validated
  # on aws-syd-test. The first 6 are verbatim from the doc (single interface).
  # ROBIN_VFIO_RESOURCE_2 + PCIDEVICE_INTEL_COM_ETH2 extend the same naming
  # pattern to the second (internal) interface for in-cluster reverse-proxy
  # deployments — a two-interface pattern not explicitly documented by F5
  # but a straightforward extension of the single-interface env vars.
  kernel_mode_env = local.is_kernel_mode ? [
    { name = "TMM_GENERIC_SOCKET_DRIVER", value = "true" },
    { name = "TMM_CALICO_ROUTER", value = "default" },
    { name = "PAL_CPU_SET", value = "0,2" },
    { name = "TMM_MAPRES_ADDL_VETHS_ON_DP", value = "TRUE" },
    { name = "ROBIN_VFIO_RESOURCE_1", value = "eth1" },
    { name = "PCIDEVICE_INTEL_COM_ETH1", value = var.external_pci_bus_id },
    { name = "ROBIN_VFIO_RESOURCE_2", value = "eth2" },
    { name = "PCIDEVICE_INTEL_COM_ETH2", value = var.internal_pci_bus_id },
  ] : []

  # TMM environment variables — these MUST be set explicitly.
  # FLO does NOT set these from CNEInstance defaults.
  tmm_env = concat(
    [
      { name = "TMM_DEFAULT_MTU", value = tostring(var.tmm_default_mtu) },
      { name = "TMM_IGNORE_GATEWAYS", value = var.tmm_ignore_gateways ? "TRUE" : "FALSE" },
    ],
    local.kernel_mode_env,
    var.tmm_extra_env
  )

  # Multus annotation override — names the data-plane interfaces eth1 / eth2
  # so they match ROBIN_VFIO_RESOURCE_1/2. Without this, Multus uses default
  # names net1 / net2 and TMM can't find its interfaces. Kernel mode only.
  multus_networks_annotation = local.is_kernel_mode ? jsonencode([
    {
      name      = var.external_nad_name
      namespace = var.namespace
      interface = "eth1"
    },
    {
      name      = var.internal_nad_name
      namespace = var.namespace
      interface = "eth2"
    }
  ]) : ""

  default_kernel_mode_annotations = local.is_kernel_mode ? {
    "k8s.v1.cni.cncf.io/networks" = local.multus_networks_annotation
  } : {}

  # Merge user-supplied tmm_pod_annotations on top of the kernel-mode defaults.
  # Anything the user sets wins (allows opt-out or override).
  tmm_annotations = merge(local.default_kernel_mode_annotations, var.tmm_pod_annotations)

  # Resources: in kernel mode default to 6Gi memory (Small + DPDK assumes 2Gi
  # which OOMKills TMM in kernel mode). User-supplied tmm_resources wins.
  default_kernel_mode_resources = local.is_kernel_mode ? {
    requests = { memory = "6Gi" }
    limits   = { memory = "6Gi" }
  } : null

  effective_resources = var.tmm_resources != null ? var.tmm_resources : local.default_kernel_mode_resources

  # tmm_block: assemble the advanced.tmm map only with fields that are set.
  # Empty annotations / null resources stay out so the operator keeps its
  # defaults for those fields.
  tmm_block = merge(
    { env = local.tmm_env },
    length(local.tmm_annotations) > 0 ? { annotations = local.tmm_annotations } : {},
    local.effective_resources != null ? { resources = local.effective_resources } : {}
  )

  # Controller environment variables
  # When cloud_provider is set (e.g. "aws"), inject CLOUD_ENV, CLOUD_PROVIDER,
  # and CLOUD_NETWORK_CONFIGMAP so the CNE controller is cloud-aware.
  cloud_env = var.cloud_provider != "" ? [
    { name = "CLOUD_ENV", value = "true" },
    { name = "CLOUD_PROVIDER", value = var.cloud_provider },
    { name = "CLOUD_NETWORK_CONFIGMAP", value = "cloud-network-mapping" },
  ] : []

  controller_env = concat(
    [
      { name = "TMM_DEFAULT_MTU", value = tostring(var.tmm_default_mtu) },
    ],
    local.cloud_env,
    var.controller_extra_env
  )

  # Optional spec fields that should only appear when set
  storage_class_field = var.storage_class_name != "" ? {
    storageClassName = var.storage_class_name
  } : {}

  # Build the CNEInstance YAML manifest
  # All feature toggles MUST be set explicitly with enabled: true/false.
  # Empty objects {} cause FLO to generate a minimal TMM template missing
  # volume mounts (/var/download), sidecars, and gRPC config setup.
  cneinstance_manifest = {
    apiVersion = "k8s.f5.com/v1"
    kind       = "CNEInstance"
    metadata = {
      name      = var.instance_name
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/name"       = var.instance_name
        "app.kubernetes.io/component"  = "cne-instance"
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/version"    = var.manifest_version
      }
    }
    spec = merge({
      manifestVersion = var.manifest_version
      deploymentSize  = var.deployment_size

      product = {
        type       = "BNK"
        gatewayAPI = true
      }

      registry = {
        uri              = "repo.f5.com"
        imagePullPolicy  = "IfNotPresent"
        imagePullSecrets = [{ name = var.far_secret_name }]
      }

      networkAttachments = [var.external_nad_name, var.internal_nad_name]

      certificate = {
        clusterIssuer = var.cluster_issuer_name
      }

      # --- Deployment mode ---
      # wholeCluster=true + dpu=false → standard Deployment (1 TMM per labeled node)
      # Without wholeCluster, TMM uses TMMReplicas count instead
      wholeCluster = var.whole_cluster

      dpu = {
        enabled = var.dpu_enabled
      }

      # --- Feature toggles ---
      # These MUST be explicitly set. Empty {} objects cause FLO to generate
      # a minimal TMM template missing /var/download volume mounts, sidecars,
      # and proper gRPC config server setup → TMM readiness gates stay False.
      dynamicRouting = {
        enabled = var.dynamic_routing_enabled
      }

      firewallACL = {
        enabled = var.firewall_acl_enabled
      }

      pseudoCNI = {
        enabled = var.pseudo_cni_enabled
      }

      coreCollection = {
        enabled = var.core_collection_enabled
      }

      # AI Intelligent Load Balancing — deploys f5-analyzer pod
      # Required for F5BigAnalyzer CRs (custom/builtin scripts)
      # CRD schema requires object format (not bare boolean despite docs)
      intelligentLB = {
        enabled = var.intelligent_lb_enabled
      }

      telemetry = {
        loggingSubsystem = {
          enabled = var.telemetry_logging_enabled
        }
        metricSubsystem = {
          enabled = var.telemetry_metrics_enabled
        }
      }

      # --- Advanced settings ---
      advanced = {
        # envDiscovery validates SR-IOV VFs, hugepages, node labels, etc.
        # Disabled by default: it checks for OVN annotations (k8s.ovn.org/node-primary-ifaddr)
        # which don't exist on AWS VPC CNI clusters, causing false failures.
        envDiscovery = {
          enabled    = var.env_discovery_enabled
          stopOnFail = var.env_discovery_stop_on_fail
        }

        cneController = {
          env = local.controller_env
        }

        tmm = local.tmm_block
      }
    }, local.storage_class_field)
  }

  # tmm-init ConfigMap content (Doc 3 page 28-29). Built when
  # var.tmm_init_enabled = true. The default tmm_init.tcl boilerplate is the
  # minimum TMM needs to set POD_IP from env and reload user_conf.tcl every
  # 1s. Anything else (Diameter/GTP profiles, pools, snatpools, bigdb tweaks)
  # goes into var.tmm_init_extra_tcl.

  tmm_init_default_tcl = <<-EOT
    set_from_env POD_IP POD_IP [info hostname]
    file_reload {
      file_name /opt/lib/tmm/user_conf.tcl
      interval 1
    }
  EOT

  tmm_init_tcl = local.tmm_init_default_tcl != "" && var.tmm_init_extra_tcl != "" ? "${local.tmm_init_default_tcl}\n${var.tmm_init_extra_tcl}" : local.tmm_init_default_tcl

  # user_conf.tcl: raw escape hatch wins over the structured routes list
  user_conf_routes_tcl = length(var.tmm_init_routes) == 0 ? "" : join("\n", concat(
    [
      "# Auto-generated by bnk-forge — do not edit",
      "puts \"tmm-init user_conf.tcl loaded ##\"",
    ],
    [
      for r in var.tmm_init_routes :
      "${r.description != "" ? "# ${r.description}\n" : ""}route ${cidrhost(r.destination, 0)} netmask ${cidrnetmask(r.destination)} gw ${r.gateway}"
    ]
  ))

  user_conf_tcl = var.tmm_init_user_conf_tcl_raw != "" ? var.tmm_init_user_conf_tcl_raw : local.user_conf_routes_tcl

  tmm_init_configmap = {
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "tmm-init"
      namespace = var.namespace
      labels = {
        "app.kubernetes.io/name"       = "tmm-init"
        "app.kubernetes.io/component"  = "tmm-config"
        "app.kubernetes.io/managed-by" = "bnk-forge"
        "app.kubernetes.io/part-of"    = var.instance_name
      }
    }
    data = {
      "static_conf.tcl" = ""
      "tmm_init.tcl"    = local.tmm_init_tcl
      "user_conf.tcl"   = local.user_conf_tcl
    }
  }
}

# =============================================================================
# tmm-init ConfigMap (Doc 3 page 28-29) — kernel-mode required, opt-in
# =============================================================================
# TMM auto-mounts a ConfigMap named "tmm-init" from its own namespace at
# /opt/lib/tmm/. user_conf.tcl is reloaded every 1s by the file_reload
# directive in tmm_init.tcl, so route changes propagate without a TMM restart.

resource "local_file" "tmm_init_manifest" {
  count    = var.tmm_init_enabled ? 1 : 0
  filename = "${path.module}/work/tmm-init-cm.yaml"
  content  = yamlencode(local.tmm_init_configmap)
}

resource "null_resource" "tmm_init_apply" {
  count = var.tmm_init_enabled ? 1 : 0

  triggers = {
    cm_hash    = sha256(yamlencode(local.tmm_init_configmap))
    namespace  = var.namespace
    kubeconfig = local_file.kubeconfig.filename
    name       = "tmm-init"
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Applying tmm-init ConfigMap (kernel-mode routes for TMM) ==="
      ${local.kubectl} apply -f ${local_file.tmm_init_manifest[0].filename}
      echo "tmm-init ConfigMap applied — TMM will reload user_conf.tcl within 1s"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      kubectl --kubeconfig ${self.triggers.kubeconfig} \
        -n ${self.triggers.namespace} \
        delete configmap ${self.triggers.name} --ignore-not-found
    EOT
  }

  depends_on = [
    local_file.tmm_init_manifest,
  ]
}

# =============================================================================
# CLOUD NETWORK MAPPING CONFIGMAP (AWS only)
# =============================================================================
# When cloud_provider is set, the CNE controller expects a ConfigMap mapping
# availability zones to subnet CIDRs/IDs. This tells the controller which
# subnet belongs to which AZ for cloud-aware routing and self-IP assignment.

resource "null_resource" "cloud_network_mapping" {
  count = var.cloud_provider != "" && length(var.cloud_az_subnet_mappings) > 0 ? 1 : 0

  triggers = {
    mappings_hash = sha256(jsonencode(var.cloud_az_subnet_mappings))
    namespace     = var.namespace
    kubeconfig    = local_file.kubeconfig.filename
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Creating cloud-network-mapping ConfigMap ==="
      cat <<'MANIFEST' | ${local.kubectl} apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloud-network-mapping
  namespace: ${var.namespace}
data:
  config.yaml: |
    availability_zones:
%{for mapping in var.cloud_az_subnet_mappings~}
      - name: "${mapping.az}"
        subnets:
%{for subnet in mapping.subnets~}
          - cidr: "${subnet.cidr}"
            subnet_id: "${subnet.subnet_id}"
%{endfor~}
%{endfor~}
MANIFEST
      echo "cloud-network-mapping ConfigMap created"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "=== Deleting cloud-network-mapping ConfigMap ==="
      kubectl --kubeconfig ${self.triggers.kubeconfig} delete configmap cloud-network-mapping \
        -n ${self.triggers.namespace} 2>/dev/null || \
      echo "ConfigMap already deleted or not found"
    EOT
  }
}

# =============================================================================
# WRITE MANIFEST TO FILE
# =============================================================================

resource "local_file" "cneinstance_manifest" {
  filename = "${path.module}/work/cneinstance.yaml"
  content  = yamlencode(local.cneinstance_manifest)
}

# =============================================================================
# CREATE / UPDATE CNEInstance
# =============================================================================

resource "null_resource" "cneinstance" {
  triggers = {
    manifest_hash = sha256(yamlencode(local.cneinstance_manifest))
    name          = var.instance_name
    namespace     = var.namespace
    kubeconfig    = local_file.kubeconfig.filename
    # Run every apply — if the CNEInstance CR is deleted out-of-band (cluster
    # disruption, manual cleanup, bnk_cleanup destroy), manifest_hash won't
    # change and Terraform won't detect the drift. kubectl apply is idempotent.
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Creating/Updating CNEInstance ${var.instance_name} ==="

      # Apply the manifest (creates or updates)
      ${local.kubectl} apply -f ${local_file.cneinstance_manifest.filename} 2>&1

      if [ $? -ne 0 ]; then
        echo "ERROR: Failed to apply CNEInstance manifest"
        echo "Checking if CRD exists..."
        ${local.kubectl} get crd cneinstances.k8s.f5.com 2>/dev/null || echo "CRD not found — FLO may not be ready"
        exit 1
      fi

      echo "CNEInstance ${var.instance_name} applied successfully"
    EOT
  }

  # Destroy: delete the CNEInstance CR
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "=== Deleting CNEInstance ${self.triggers.name} ==="
      kubectl --kubeconfig ${self.triggers.kubeconfig} delete cneinstance ${self.triggers.name} \
        -n ${self.triggers.namespace} \
        --timeout=300s 2>/dev/null || \
      echo "CNEInstance ${self.triggers.name} already deleted or timed out"
    EOT
  }

  depends_on = [
    local_file.cneinstance_manifest,
    null_resource.cloud_network_mapping,
    # Apply tmm-init CM first (when enabled) so TMM picks up routes on its
    # FIRST start. Without this dep TMM would still load it on the next
    # 1-second file_reload tick, but routing would briefly leak via the
    # internal `tmm` interface — visible as ICMP/TCP timeouts on initial
    # client traffic.
    null_resource.tmm_init_apply,
  ]
}

# =============================================================================
# WAIT FOR CNEInstance TO BECOME AVAILABLE
# =============================================================================
# FLO sees the CNEInstance CR and starts deploying components.
# This takes several minutes. We wait for Available=True condition.

resource "null_resource" "wait_for_available" {
  depends_on = [null_resource.cneinstance]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Waiting for CNEInstance ${var.instance_name} to become Available ==="
      echo "This typically takes 3-8 minutes as FLO deploys all BNK components..."

      # Wait up to 10 minutes for Available condition
      TIMEOUT=600
      INTERVAL=15
      ELAPSED=0

      while [ $ELAPSED -lt $TIMEOUT ]; do
        # Get the Available condition
        STATUS=$(${local.kubectl} get cneinstance ${var.instance_name} \
          -n ${var.namespace} \
          -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)

        REASON=$(${local.kubectl} get cneinstance ${var.instance_name} \
          -n ${var.namespace} \
          -o jsonpath='{.status.conditions[?(@.type=="Available")].reason}' 2>/dev/null)

        if [ "$STATUS" = "True" ]; then
          echo "CNEInstance ${var.instance_name} is Available!"
          break
        fi

        echo "  Status: $STATUS, Reason: $REASON ($${ELAPSED}s elapsed)"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
      done

      if [ "$STATUS" != "True" ]; then
        echo ""
        echo "WARNING: CNEInstance not yet Available after $${TIMEOUT}s"
        echo "This may be normal for first deployment. Check FLO logs:"
        echo "  kubectl logs -n ${var.namespace} -l app=flo --tail=50"
        echo ""
        echo "Current CNEInstance status:"
        ${local.kubectl} get cneinstance ${var.instance_name} -n ${var.namespace} -o yaml 2>/dev/null | grep -A5 "conditions:" || true
        # Don't fail — the instance may still be deploying
      fi
    EOT
  }
}

# =============================================================================
# VERIFY PODS ARE RUNNING
# =============================================================================

resource "null_resource" "verify_pods" {
  depends_on = [null_resource.wait_for_available]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Verifying BNK Pods ==="

      KUBECTL="${local.kubectl}"

      echo ""
      echo "--- Pods in ${var.namespace} ---"
      $KUBECTL get pods -n ${var.namespace} -o wide 2>/dev/null

      echo ""
      echo "--- CNEInstance Status ---"
      $KUBECTL get cneinstance ${var.instance_name} -n ${var.namespace} 2>/dev/null

      echo ""
      echo "--- Component Summary ---"
      # Count running pods
      TOTAL=$($KUBECTL get pods -n ${var.namespace} --no-headers 2>/dev/null | wc -l)
      RUNNING=$($KUBECTL get pods -n ${var.namespace} --no-headers 2>/dev/null | grep -c "Running" || true)
      COMPLETED=$($KUBECTL get pods -n ${var.namespace} --no-headers 2>/dev/null | grep -c "Completed" || true)

      echo "Total pods: $TOTAL"
      echo "Running: $RUNNING"
      echo "Completed: $COMPLETED"

      # Check for key components
      echo ""
      echo "--- Key Components ---"
      for component in flo cne-controller tmm cwc dssm observer otel rabbit fluentd; do
        COUNT=$($KUBECTL get pods -n ${var.namespace} --no-headers 2>/dev/null | grep -c "$component" || true)
        if [ "$COUNT" -gt 0 ]; then
          echo "  OK: $component ($COUNT pods)"
        else
          echo "  MISSING: $component"
        fi
      done

      echo ""
      echo "CNEInstance verification complete"
    EOT
  }
}
