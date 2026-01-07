# main.tf - High Performance EKS Node Group with S3 and DPDK setup

# Data sources for dependencies
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

data "aws_subnets" "private_internal" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  
  filter {
    name   = "tag:Name"
    values = ["*private-internal*"]
  }
}

data "aws_subnets" "private_external" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  
  filter {
    name   = "tag:Name"
    values = ["*private-external*"]
  }
}

data "aws_security_group" "vpc_sg" {
  id = var.vpc_security_group_id
}

data "aws_security_group" "cluster_sg" {
  filter {
    name   = "group-name"
    values = ["eks-cluster-sg-${var.cluster_name}-*"]
  }
  
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
  }
  
  # F5 SPK specific node labels for x86_64
  x86_f5_spk_labels = var.f5_spk_enabled ? {
    "f5.com/spk-node"           = "true"
    "f5.com/tmm-capable"        = "true" 
    "f5.com/numa-node"          = tostring(var.f5_numa_node)
    "f5.com/cpu-cores"          = tostring(var.f5_tmm_cpu_cores)
    "f5.com/architecture"       = "x86_64"
    "spk"                       = "tmm"
    "workload-type"             = "high-performance"
    "sriov-capable"             = "true"
    "dpdk-enabled"              = "true"
  } : {}
  
  # Combine all x86_64 labels
  x86_combined_node_labels = merge({
    "node-type"     = "high-performance"
    "sriov"         = "enabled"
    "dpdk"          = "enabled"
    "is_worker"     = "true"
    "architecture"  = "x86_64"
  }, local.x86_f5_spk_labels)
}

# ==============================================
# S3 BUCKET FOR DPDK SCRIPTS
# ==============================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "dpdk_scripts" {
  bucket = "${var.project_name}-dpdk-scripts-${random_id.bucket_suffix.hex}"
  
  tags = local.common_tags
}

# Block public access
resource "aws_s3_bucket_public_access_block" "dpdk_scripts" {
  bucket = aws_s3_bucket.dpdk_scripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable server-side encryption by default
resource "aws_s3_bucket_server_side_encryption_configuration" "dpdk_scripts" {
  bucket = aws_s3_bucket.dpdk_scripts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Enforce SSL/TLS for all requests
resource "aws_s3_bucket_policy" "enforce_ssl" {
  bucket = aws_s3_bucket.dpdk_scripts.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.dpdk_scripts.arn,
          "${aws_s3_bucket.dpdk_scripts.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Upload DPDK scripts to S3
resource "aws_s3_object" "dpdk_setup_script" {
  bucket = aws_s3_bucket.dpdk_scripts.id
  key    = "dpdk-setup.sh"
  source = "${path.module}/scripts/dpdk-setup.sh"
  etag   = filemd5("${path.module}/scripts/dpdk-setup.sh")
  
  tags = local.common_tags
}

resource "aws_s3_object" "dpdk_devbind" {
  bucket = aws_s3_bucket.dpdk_scripts.id
  key    = "dpdk-devbind.py"
  source = "${path.module}/scripts/dpdk-devbind.py"
  etag   = filemd5("${path.module}/scripts/dpdk-devbind.py")
  
  tags = local.common_tags
}

resource "aws_s3_object" "sriov_init_script" {
  bucket = aws_s3_bucket.dpdk_scripts.id
  key    = "sriov-init.sh"
  source = "${path.module}/scripts/sriov-init.sh"
  etag   = filemd5("${path.module}/scripts/sriov-init.sh")
  
  tags = local.common_tags
}

resource "aws_s3_object" "config_sriov_script" {
  bucket = aws_s3_bucket.dpdk_scripts.id
  key    = "config-sriov.sh"
  source = "${path.module}/scripts/config-sriov.sh"
  etag   = filemd5("${path.module}/scripts/config-sriov.sh")
  
  tags = local.common_tags
}

resource "aws_s3_object" "dpdk_resource_builder" {
  bucket = aws_s3_bucket.dpdk_scripts.id
  key    = "dpdk-resource-builder.py"
  source = "${path.module}/scripts/dpdk-resource-builder.py"
  etag   = filemd5("${path.module}/scripts/dpdk-resource-builder.py")
  
  tags = local.common_tags
}

# Upload systemd service files
resource "aws_s3_object" "sriov_init_service" {
  bucket = aws_s3_bucket.dpdk_scripts.id
  key    = "sriov-init.service"
  source = "${path.module}/scripts/sriov-init.service"
  etag   = filemd5("${path.module}/scripts/sriov-init.service")
  
  tags = local.common_tags
}

resource "aws_s3_object" "config_sriov_service" {
  bucket = aws_s3_bucket.dpdk_scripts.id
  key    = "config-sriov.service"
  source = "${path.module}/scripts/config-sriov.service"
  etag   = filemd5("${path.module}/scripts/config-sriov.service")
  
  tags = local.common_tags
}

# ==============================================
# S3 IAM POLICY FOR NODEGROUP ROLE
# ==============================================

# IAM policy for nodes to access S3 DPDK scripts
resource "aws_iam_policy" "s3_dpdk_access" {
  name        = "${var.project_name}-s3-dpdk-access"
  description = "Allow nodes to access S3 DPDK scripts"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.dpdk_scripts.arn,
          "${aws_s3_bucket.dpdk_scripts.arn}/*"
        ]
      }
    ]
  })
}

# Attach S3 policy to the existing nodegroup role from security module
resource "aws_iam_role_policy_attachment" "nodegroup_s3_access" {
  policy_arn = aws_iam_policy.s3_dpdk_access.arn
  role       = var.nodegroup_role_name
}

# ==============================================
# LAUNCH TEMPLATE
# ==============================================

resource "aws_launch_template" "x86_high_perf_nodegroup" {
  name_prefix   = "${var.project_name}-x86-high-perf-"
  instance_type = var.instance_type
  key_name      = var.key_pair_name
  
  vpc_security_group_ids = [
    var.vpc_security_group_id,
    data.aws_security_group.cluster_sg.id
  ]
  
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 2
  }
  
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = var.node_volume_size
      volume_type = "gp3"
      iops        = 3000
      throughput  = 125
      encrypted   = true
      delete_on_termination = true
    }
  }
  
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.project_name}-x86-high-perf-worker"
      "Architecture" = "x86_64"
      "NodeType" = "high-performance"
    }, var.f5_spk_enabled ? {
      "f5.com/spk-node" = "true"
      "f5.com/tmm-node" = "true"
    } : {})
  }
  
  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${var.project_name}-x86-high-perf-volume"
    })
  }
  
  # Use original compact_userdata.sh with corrected variable names
  user_data = base64encode(templatefile("${path.module}/scripts/compact_userdata.sh", {
    s3_bucket_name     = aws_s3_bucket.dpdk_scripts.id
    region             = var.region
    hugepages_2mi      = var.hugepages_2mi
    hugepages_1gi      = var.hugepages_1gi
    f5_spk_enabled     = var.f5_spk_enabled ? "true" : "false"
    f5_tmm_cpu_cores   = var.f5_tmm_cpu_cores
    f5_numa_node       = var.f5_numa_node
  }))
}

# ==============================================
# EKS NODE GROUP
# ==============================================

resource "aws_eks_node_group" "x86_high_perf" {
  cluster_name    = var.cluster_name
  node_group_name = "${var.project_name}-x86-high-perf-nodes"
  node_role_arn   = var.nodegroup_role_arn
  subnet_ids      = data.aws_subnets.private_internal.ids
  
  scaling_config {
    desired_size = var.node_count
    max_size     = var.node_count + 1
    min_size     = 1
  }
  
  launch_template {
    id      = aws_launch_template.x86_high_perf_nodegroup.id
    version = "$Latest"
  }
  
  capacity_type = var.capacity_type
  ami_type = "AL2_x86_64"
  
  update_config {
    max_unavailable = 1
  }
  
  # x86_64 labels
  labels = local.x86_combined_node_labels
  
  # High-performance taint
  dynamic "taint" {
    for_each = var.enable_taints ? [
      {
        key    = "high-performance"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    ] : []
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }
  
  # F5 SPK specific taint
  dynamic "taint" {
    for_each = var.f5_spk_enabled && var.enable_taints ? [
      {
        key    = "f5.com/spk-node"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    ] : []
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.nodegroup_s3_access,
  ]
  
  tags = merge(local.common_tags, {
    "Architecture" = "x86_64"
  })
}

# ==============================================
# WAIT FOR NODES
# ==============================================

resource "null_resource" "wait_for_x86_nodes" {
  depends_on = [aws_eks_node_group.x86_high_perf]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for x86_64 high-performance nodes to be ready..."
      sleep 60
      
      # Wait for nodes to join the cluster
      timeout 600 bash -c '
        while [[ $(kubectl get nodes -l node-type=high-performance,architecture=x86_64 --no-headers 2>/dev/null | wc -l) -lt ${var.node_count} ]]; do
          echo "Waiting for x86_64 nodes to be ready..."
          sleep 10
        done
      '
      
      echo "x86_64 high-performance nodes are ready!"
      kubectl get nodes -l node-type=high-performance,architecture=x86_64
    EOT
  }
}

# ==============================================
# ENI ATTACHMENT MANAGER
# ==============================================

# ConfigMap for ENI attachment scripts
resource "kubernetes_config_map" "eni_attachment_scripts" {
  depends_on = [aws_eks_node_group.x86_high_perf]
  
  metadata {
    name      = "eni-attachment-scripts"
    namespace = "kube-system"
  }
  
  data = {
    "eni_attachment_manager.py" = file("${path.module}/scripts/eni_attachment_manager.py")
  }
}

# ServiceAccount for ENI attachment
resource "kubernetes_service_account" "eni_attachment_manager" {
  depends_on = [aws_eks_node_group.x86_high_perf]
  
  metadata {
    name      = "eni-attachment-manager"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = var.eni_attachment_manager_role_arn
    }
  }
}

# Deploy ENI attachment manager
resource "kubernetes_manifest" "eni_attachment_daemonset" {
  depends_on = [
    kubernetes_service_account.eni_attachment_manager,
    kubernetes_config_map.eni_attachment_scripts
  ]
  
  manifest = yamldecode(templatefile("${path.module}/manifests/eni-attachment-daemonset.yaml", {
    region                    = var.region
    vpc_security_group_id     = var.vpc_security_group_id
    cluster_security_group_id = data.aws_security_group.cluster_sg.id
  }))
}

# Wait for ENI attachment to complete
resource "null_resource" "wait_for_eni_attachment" {
  depends_on = [kubernetes_manifest.eni_attachment_daemonset]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for ENI attachment to complete..."
      sleep 60
      echo "ENI attachment completed!"
    EOT
  }
}

# ==============================================
# MULTUS CNI DEPLOYMENT
# ==============================================

resource "kubernetes_manifest" "multus_serviceaccount" {
  depends_on = [null_resource.wait_for_x86_nodes]
  
  manifest = yamldecode(file("${path.module}/manifests/multus-serviceaccount.yaml"))
}

resource "kubernetes_manifest" "multus_clusterrole" {
  depends_on = [kubernetes_manifest.multus_serviceaccount]
  
  manifest = yamldecode(file("${path.module}/manifests/multus-clusterrole.yaml"))
}

resource "kubernetes_manifest" "multus_clusterrolebinding" {
  depends_on = [kubernetes_manifest.multus_clusterrole]
  
  manifest = yamldecode(file("${path.module}/manifests/multus-clusterrolebinding.yaml"))
}

resource "kubernetes_manifest" "multus_daemon_config" {
  depends_on = [kubernetes_manifest.multus_clusterrolebinding]
  
  manifest = yamldecode(file("${path.module}/manifests/multus-daemon-config.yaml"))
}

resource "kubernetes_manifest" "multus_daemonset" {
  depends_on = [kubernetes_manifest.multus_daemon_config]
  
  manifest = yamldecode(file("${path.module}/manifests/multus-daemonset.yaml"))
}

# Wait for Multus to be ready and CRDs to be installed
resource "null_resource" "wait_for_multus" {
  depends_on = [kubernetes_manifest.multus_daemonset]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Multus CNI to be ready..."
      kubectl wait --for=condition=ready pod -l app=multus -n kube-system --timeout=300s
      
      echo "Waiting for NetworkAttachmentDefinition CRD to be available..."
      timeout 300 bash -c '
        while ! kubectl get crd network-attachment-definitions.k8s.cni.cncf.io >/dev/null 2>&1; do
          echo "Waiting for NetworkAttachmentDefinition CRD..."
          sleep 10
        done
      '
      
      echo "Multus CNI and CRDs are ready!"
    EOT
  }
}

# ==============================================
# SR-IOV CNI DEPLOYMENT
# ==============================================

resource "kubernetes_manifest" "sriov_cni_installer" {
  depends_on = [null_resource.wait_for_multus]
  
  manifest = yamldecode(file("${path.module}/manifests/sriov-cni-installer-x86.yaml"))
}

# Wait for SR-IOV CNI installer
resource "null_resource" "wait_for_sriov_cni" {
  depends_on = [kubernetes_manifest.sriov_cni_installer]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for SR-IOV CNI installer to complete..."
      kubectl wait --for=condition=ready pod -l app=sriov-cni-installer -n kube-system --timeout=300s || true
      sleep 30
      echo "SR-IOV CNI installation completed!"
    EOT
  }
}

# ==============================================
# SR-IOV DEVICE PLUGIN DEPLOYMENT
# ==============================================

resource "kubernetes_manifest" "sriov_serviceaccount" {
  depends_on = [null_resource.wait_for_sriov_cni]
  
  manifest = yamldecode(file("${path.module}/manifests/sriov-serviceaccount.yaml"))
}

resource "kubernetes_manifest" "sriovdp_config" {
  depends_on = [kubernetes_manifest.sriov_serviceaccount]
  
  manifest = yamldecode(file("${path.module}/manifests/sriovdp-config.yaml"))
}

resource "kubernetes_manifest" "sriov_device_plugin" {
  depends_on = [kubernetes_manifest.sriovdp_config]
  
  manifest = yamldecode(file("${path.module}/manifests/sriov-daemonset.yaml"))
}

# Wait for SR-IOV Device Plugin
resource "null_resource" "wait_for_sriov_device_plugin" {
  depends_on = [kubernetes_manifest.sriov_device_plugin]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for SR-IOV Device Plugin to be ready..."
      kubectl wait --for=condition=ready pod -l name=sriov-device-plugin -n kube-system --timeout=300s || true
      sleep 30
      echo "SR-IOV Device Plugin is ready!"
    EOT
  }
}

# ==============================================
# DPDK CONFIGURATOR DEPLOYMENT
# ==============================================

resource "kubernetes_manifest" "dpdk_serviceaccount" {
  depends_on = [null_resource.wait_for_sriov_device_plugin]
  
  manifest = yamldecode(file("${path.module}/manifests/dpdk-serviceaccount.yaml"))
}

resource "kubernetes_manifest" "dpdk_clusterrole" {
  depends_on = [kubernetes_manifest.dpdk_serviceaccount]
  
  manifest = yamldecode(file("${path.module}/manifests/dpdk-clusterrole.yaml"))
}

resource "kubernetes_manifest" "dpdk_clusterrolebinding" {
  depends_on = [kubernetes_manifest.dpdk_clusterrole]
  
  manifest = yamldecode(file("${path.module}/manifests/dpdk-clusterrolebinding.yaml"))
}

resource "kubernetes_manifest" "dpdk_daemonset" {
  depends_on = [kubernetes_manifest.dpdk_clusterrolebinding]
  
  manifest = yamldecode(file("${path.module}/manifests/dpdk-daemonset.yaml"))
}

# ==============================================
# FINAL VERIFICATION
# ==============================================

resource "null_resource" "verify_dpdk_setup" {
  depends_on = [
    kubernetes_manifest.dpdk_daemonset
  ]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "=== x86_64 High-Performance Nodes Setup Verification ==="
      echo "Architecture: x86_64"
      echo "Instance Type: ${var.instance_type}"
      echo "F5 SPK enabled: ${var.f5_spk_enabled}"
      echo "Taints enabled: ${var.enable_taints}"
      echo "S3 bucket: ${aws_s3_bucket.dpdk_scripts.id}"
      echo "Multus IP Manager: ${var.ecr_registry}/multus-ip-manager:${var.multus_container_version}"
      echo
      
      kubectl get nodes -l architecture=x86_64 --show-labels
      echo
      
      echo "Checking DaemonSet deployments..."
      kubectl get ds -n kube-system -l app=multus
      kubectl get ds -n kube-system -l app=sriov-cni-installer  
      kubectl get ds -n kube-system -l app=sriovdp
      kubectl get ds -n kube-system -l app=dpdk-configurator
      kubectl get ds -n kube-system -l app=multus-ip-manager
      echo
      
      echo "Checking pod status..."
      kubectl get pods -n kube-system -l app=multus
      kubectl get pods -n kube-system -l app=sriov-cni-installer
      kubectl get pods -n kube-system -l app=sriovdp  
      kubectl get pods -n kube-system -l app=dpdk-configurator
      kubectl get pods -n kube-system -l app=multus-ip-manager
      echo
      
      echo "=== Infrastructure Ready for F5 SPK Installation ==="
      echo "Multus IP Manager will handle ENI assignments for TMM pods"
      echo "SR-IOV resources available for F5 TMM pods"
    EOT
  }
}

# Cleanup resources
resource "null_resource" "cleanup" {
  triggers = {
    nodegroup_name = aws_eks_node_group.x86_high_perf.node_group_name
  }
  
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Cleaning up High-Performance Nodes resources..."
      kubectl delete ds dpdk-configurator -n kube-system --ignore-not-found=true
      kubectl delete ds sriov-cni-installer-x86 -n kube-system --ignore-not-found=true
      kubectl delete ds kube-sriov-device-plugin-amd64 -n kube-system --ignore-not-found=true
      kubectl delete ds kube-multus-ds -n kube-system --ignore-not-found=true
      kubectl delete network-attachment-definitions --all --ignore-not-found=true
      kubectl delete sa multus sriov-device-plugin -n kube-system --ignore-not-found=true
      kubectl delete clusterrole multus dpdk-configurator --ignore-not-found=true
      kubectl delete clusterrolebinding multus dpdk-configurator --ignore-not-found=true
      kubectl delete configmap multus-daemon-config -n kube-system --ignore-not-found=true
      echo "Cleanup completed"
    EOT
  }
}