# bnk/bnk-vlans/main.tf
# F5SPKVlan CRs — TMM VLAN Self IPs
#
# Creates F5SPKVlan custom resources that tell TMM which IP addresses to use
# on its data-plane interfaces. TMM configures these IPs on its interfaces
# itself — they are NOT assigned by Multus IPAM (the NADs have no IPAM).
#
# Reference: https://clouddocs.f5.com/bigip-next-for-kubernetes/latest/bnk-configure-network.html
#
# Uses kubectl apply because the F5SPKVlan CRD is installed by FLO at runtime,
# not available at plan time (same pattern as cneinstance module).
#
# Interface mapping (determined by order in CNEInstance networkAttachments):
#   1.1 = external (first NAD listed = external-netdevice)
#   1.2 = internal (second NAD listed = internal-netdevice)

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

  # Prefix length from subnet CIDR (e.g. "10.0.10.0/24" → 24)
  external_prefixlen = tonumber(split("/", var.external_subnet_cidrs[0])[1])
  internal_prefixlen = tonumber(split("/", var.internal_subnet_cidrs[0])[1])

  # Auto-derive self IPs from subnet CIDR when not explicitly provided.
  # Uses .240 of the first subnet's network prefix (e.g. "10.0.10.0/24" → "10.0.10.240").
  # This avoids hardcoded IPs that don't match the actual cloud subnets.
  _external_network = split("/", var.external_subnet_cidrs[0])[0]
  _external_octets  = split(".", local._external_network)
  _external_auto_ip = "${local._external_octets[0]}.${local._external_octets[1]}.${local._external_octets[2]}.240"

  _internal_network = split("/", var.internal_subnet_cidrs[0])[0]
  _internal_octets  = split(".", local._internal_network)
  _internal_auto_ip = "${local._internal_octets[0]}.${local._internal_octets[1]}.${local._internal_octets[2]}.240"

  effective_external_self_ips = length(var.external_self_ips) > 0 ? var.external_self_ips : [local._external_auto_ip]
  effective_internal_self_ips = length(var.internal_self_ips) > 0 ? var.internal_self_ips : [local._internal_auto_ip]
}

# =============================================================================
# WRITE VLAN MANIFESTS
# =============================================================================

resource "local_file" "vlan_manifests" {
  filename = "${path.module}/work/vlans.yaml"
  content  = <<-YAML
apiVersion: k8s.f5net.com/v1
kind: F5SPKVlan
metadata:
  name: external
  namespace: ${var.namespace}
spec:
  name: external
  interfaces:
  - "1.1"
  mtu: ${var.mtu}
  selfip_v4s:
%{for ip in local.effective_external_self_ips~}
  - ${ip}
%{endfor~}
  prefixlen_v4: ${local.external_prefixlen}
%{if var.auto_lasthop != ""~}
  auto_lasthop: "${var.auto_lasthop}"
%{endif~}
---
apiVersion: k8s.f5net.com/v1
kind: F5SPKVlan
metadata:
  name: internal
  namespace: ${var.namespace}
spec:
  name: internal
  internal: true
  interfaces:
  - "1.2"
  mtu: ${var.mtu}
  selfip_v4s:
%{for ip in local.effective_internal_self_ips~}
  - ${ip}
%{endfor~}
  prefixlen_v4: ${local.internal_prefixlen}
%{if var.auto_lasthop != ""~}
  auto_lasthop: "${var.auto_lasthop}"
%{endif~}
YAML
}

# =============================================================================
# APPLY VLAN CRs
# =============================================================================

resource "null_resource" "vlans" {
  triggers = {
    manifest_hash = sha256(local_file.vlan_manifests.content)
    namespace     = var.namespace
    kubeconfig    = local_file.kubeconfig.filename
    # Run every apply — if VLAN CRs are deleted out-of-band, manifest_hash
    # won't change and Terraform misses the drift. kubectl apply is idempotent.
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Applying F5SPKVlan CRs ==="

      # Wait for the F5SPKVlan CRD to exist (FLO installs it)
      TIMEOUT=120
      ELAPSED=0
      while [ $ELAPSED -lt $TIMEOUT ]; do
        ${local.kubectl} get crd f5-spk-vlans.k8s.f5net.com >/dev/null 2>&1 && break
        echo "  Waiting for F5SPKVlan CRD ($${ELAPSED}s)..."
        sleep 10
        ELAPSED=$((ELAPSED + 10))
      done

      if ! ${local.kubectl} get crd f5-spk-vlans.k8s.f5net.com >/dev/null 2>&1; then
        echo "ERROR: F5SPKVlan CRD not found after $${TIMEOUT}s — is FLO deployed?"
        exit 1
      fi

      kubeconfig="${local_file.kubeconfig.filename}"
      namespace="${var.namespace}"
      echo "Waiting for F5 validation webhook..."
      WEBHOOK_TIMEOUT=150
      WEBHOOK_ELAPSED=0
      while [ $WEBHOOK_ELAPSED -lt $WEBHOOK_TIMEOUT ]; do
        ENDPOINT_IP=$(kubectl --kubeconfig $${kubeconfig} get endpoints f5-validation-svc \
          -n $${namespace} -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
        if [ -n "$ENDPOINT_IP" ]; then
          echo "F5 validation webhook ready (endpoint: $ENDPOINT_IP)"
          break
        fi
        echo "  Waiting for f5-validation-svc endpoint ($${WEBHOOK_ELAPSED}s)..."
        sleep 5
        WEBHOOK_ELAPSED=$((WEBHOOK_ELAPSED + 5))
      done
      if [ $WEBHOOK_ELAPSED -ge $WEBHOOK_TIMEOUT ]; then
        echo "WARNING: F5 validation webhook not ready after $${WEBHOOK_TIMEOUT}s — apply may fail"
      fi

      ${local.kubectl} apply -f ${local_file.vlan_manifests.filename} 2>&1

      if [ $? -ne 0 ]; then
        echo "ERROR: Failed to apply VLAN manifests"
        exit 1
      fi

      echo ""
      echo "=== VLAN CRs applied ==="
      ${local.kubectl} get f5-spk-vlans.k8s.f5net.com -n ${var.namespace} 2>/dev/null
    EOT
  }

  # Destroy: delete the VLAN CRs
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "=== Deleting F5SPKVlan CRs ==="
      kubectl --kubeconfig ${self.triggers.kubeconfig} delete f5-spk-vlans.k8s.f5net.com external internal \
        -n ${self.triggers.namespace} \
        --timeout=60s 2>/dev/null || \
      echo "VLAN CRs already deleted or not found"
    EOT
  }

  depends_on = [local_file.vlan_manifests]
}

# =============================================================================
# AWS ENI SECONDARY IP REGISTRATION (Cloud-only)
# =============================================================================
# On AWS, secondary IPs MUST be registered on the ENI for the Nitro hypervisor
# ARP proxy to work. Unregistered IPs are blackholed even on the same subnet.
#
# This discovers ENIs by tag (external: ENIType=external-dpdk, internal: by
# subnet and instance) and registers self-IPs + gateway VIPs as secondary IPs.
#
# Only runs when aws_region is set (i.e. cloud deployment). On-prem/DPU
# deployments skip this entirely.

resource "null_resource" "register_eni_secondary_ips" {
  count = var.aws_region != "" ? 1 : 0

  triggers = {
    external_self_ips = join(",", local.effective_external_self_ips)
    internal_self_ips = join(",", local.effective_internal_self_ips)
    gateway_vips      = join(",", var.gateway_vips)
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Registering secondary IPs on AWS ENIs ==="

      # Get the HP node instance ID (node with app=f5-tmm label, set by high-performance-nodes module)
      INSTANCE_ID=$(${local.kubectl} get nodes -l app=f5-tmm \
        -o jsonpath='{.items[0].spec.providerID}' 2>/dev/null | sed 's|.*/||')

      if [ -z "$INSTANCE_ID" ]; then
        echo "WARNING: Could not find HP node with app=f5-tmm label"
        echo "ENI secondary IP registration skipped — register manually:"
        echo "  aws ec2 assign-private-ip-addresses --network-interface-id <ENI_ID> --private-ip-addresses ${join(" ", local.effective_external_self_ips)} ${join(" ", var.gateway_vips)}"
        exit 0
      fi

      echo "HP node instance: $INSTANCE_ID"

      # --- External ENI: find by tag ENIType=external-dpdk ---
      EXT_ENI=$(aws ec2 describe-network-interfaces \
        --region ${var.aws_region} \
        --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" \
                  "Name=tag:ENIType,Values=external-dpdk" \
        --query 'NetworkInterfaces[0].NetworkInterfaceId' \
        --output text 2>/dev/null)

      if [ "$EXT_ENI" = "None" ] || [ -z "$EXT_ENI" ]; then
        echo "WARNING: External ENI (ENIType=external-dpdk) not found on $INSTANCE_ID"
        echo "Skipping external IP registration"
      else
        echo "External ENI: $EXT_ENI"

        # Collect all IPs to register on external ENI: self-IPs + VIPs
        EXT_IPS="${join(" ", concat(local.effective_external_self_ips, var.gateway_vips))}"

        if [ -n "$EXT_IPS" ]; then
          echo "Registering on external ENI: $EXT_IPS"
          # assign-private-ip-addresses errors if IP already assigned — that's OK
          aws ec2 assign-private-ip-addresses \
            --region ${var.aws_region} \
            --network-interface-id "$EXT_ENI" \
            --private-ip-addresses $EXT_IPS 2>&1 || \
            echo "WARNING: Some external IPs may already be assigned (this is OK)"
        fi

        # Disable source/dest check (required for TMM to forward traffic)
        aws ec2 modify-network-interface-attribute \
          --region ${var.aws_region} \
          --network-interface-id "$EXT_ENI" \
          --no-source-dest-check 2>&1 || true

        echo "External ENI IPs registered"
      fi

      # --- Internal ENI: find by subnet and instance (not tagged external-dpdk) ---
      # The internal ENI is the node's secondary ENI (eth1) in the internal subnet.
      # We identify it by exclusion: attached to the instance, NOT the primary (index 0),
      # NOT tagged external-dpdk.
      INT_ENI=$(aws ec2 describe-network-interfaces \
        --region ${var.aws_region} \
        --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" \
                  "Name=subnet-id,Values=${var.internal_subnet_id}" \
        --query 'NetworkInterfaces[0].NetworkInterfaceId' \
        --output text 2>/dev/null)

      if [ "$INT_ENI" = "None" ] || [ -z "$INT_ENI" ]; then
        echo "WARNING: Internal ENI not found in subnet ${var.internal_subnet_id} on $INSTANCE_ID"
        echo "Skipping internal IP registration"
      else
        echo "Internal ENI: $INT_ENI"

        INT_IPS="${join(" ", local.effective_internal_self_ips)}"

        if [ -n "$INT_IPS" ]; then
          echo "Registering on internal ENI: $INT_IPS"
          aws ec2 assign-private-ip-addresses \
            --region ${var.aws_region} \
            --network-interface-id "$INT_ENI" \
            --private-ip-addresses $INT_IPS 2>&1 || \
            echo "WARNING: Some internal IPs may already be assigned (this is OK)"
        fi

        # Disable source/dest check
        aws ec2 modify-network-interface-attribute \
          --region ${var.aws_region} \
          --network-interface-id "$INT_ENI" \
          --no-source-dest-check 2>&1 || true

        echo "Internal ENI IPs registered"
      fi

      echo ""
      echo "=== ENI secondary IP registration complete ==="
    EOT
  }

  depends_on = [null_resource.vlans]
}

# =============================================================================
# WAIT FOR VLANS TO BE PROGRAMMED
# =============================================================================

resource "null_resource" "wait_for_programmed" {
  depends_on = [
    null_resource.vlans,
    null_resource.register_eni_secondary_ips,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Waiting for VLAN CRs to be Programmed ==="

      TIMEOUT=180
      INTERVAL=10
      ELAPSED=0

      while [ $ELAPSED -lt $TIMEOUT ]; do
        EXT_STATUS=$(${local.kubectl} get f5-spk-vlans.k8s.f5net.com external \
          -n ${var.namespace} \
          -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null)
        INT_STATUS=$(${local.kubectl} get f5-spk-vlans.k8s.f5net.com internal \
          -n ${var.namespace} \
          -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null)

        if [ "$EXT_STATUS" = "True" ] && [ "$INT_STATUS" = "True" ]; then
          echo "Both VLANs are Programmed!"
          break
        fi

        echo "  external=$EXT_STATUS internal=$INT_STATUS ($${ELAPSED}s)"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
      done

      if [ "$EXT_STATUS" != "True" ] || [ "$INT_STATUS" != "True" ]; then
        echo ""
        echo "WARNING: VLANs not yet Programmed after $${TIMEOUT}s"
        echo "This may resolve once TMM readiness gates go True."
        echo "Current status:"
        ${local.kubectl} get f5-spk-vlans.k8s.f5net.com -n ${var.namespace} -o yaml 2>/dev/null | grep -A5 "Programmed" || true
      fi
    EOT
  }
}
