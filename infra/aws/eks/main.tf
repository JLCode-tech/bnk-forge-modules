# infrastructure-modules/foundation/eks/main.tf

data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

# Get the latest EKS optimized AMI
data "aws_ami" "eks_worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.kubernetes_version}-v*"]
  }
  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

# KMS Key for EKS Secret Encryption
resource "aws_kms_key" "eks_secrets" {
  description             = "KMS key for EKS secret encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-eks-secrets-key"
  })
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.project_name}-eks-secrets-key"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

# EKS Cluster - using security module IAM roles
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-cluster"
  role_arn = var.eks_cluster_role_arn
  version  = var.kubernetes_version

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
    resources = ["secrets"]
  }

  vpc_config {
    subnet_ids = concat(
      var.private_external_subnet_ids,
      var.private_internal_subnet_ids
    )
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = [var.user_ip]
    security_group_ids      = [var.vpc_security_group_id]
  }

  depends_on = [
    # No explicit depends_on needed - Terragrunt handles dependencies
  ]

  tags = var.common_tags
}

# Launch template for node group instances with proper naming
resource "aws_launch_template" "nodegroup" {
  name_prefix   = "${var.project_name}-nodegroup-"
  image_id      = data.aws_ami.eks_worker.id
  instance_type = var.instance_type
  key_name      = var.infrastructure_key_name
  
  vpc_security_group_ids = [var.vpc_security_group_id]
  
  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name = "${var.project_name}-worker-node"
    })
  }
  
  tag_specifications {
    resource_type = "volume"
    tags = merge(var.common_tags, {
      Name = "${var.project_name}-worker-node-volume"
    })
  }
  
  user_data = base64encode(templatefile("${path.module}/templates/nodegroup_userdata.sh", {
    cluster_name = "${var.project_name}-cluster"
    region       = var.aws_region
  }))
  
  tags = var.common_tags
}

# EKS Node Group with launch template
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = var.nodegroup_role_arn
  subnet_ids      = var.private_external_subnet_ids
  
  scaling_config {
    desired_size = var.node_count
    max_size     = var.node_count + 1
    min_size     = 1
  }
  
  # Use launch template for proper instance naming
  launch_template {
    id      = aws_launch_template.nodegroup.id
    version = "$Latest"
  }
  
  tags = var.common_tags
}

# =============================================================================
# OIDC PROVIDER CONFIGURATION
# =============================================================================

# Data source for TLS certificate to get OIDC thumbprint
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# IAM OIDC provider for the EKS cluster (Required for IRSA)
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-eks-oidc-provider"
  })

  depends_on = [aws_eks_cluster.main]
}

# =============================================================================
# EBS CSI DRIVER CONFIGURATION
# =============================================================================

# IAM role for EBS CSI driver
resource "aws_iam_role" "ebs_csi_driver" {
  name = "${var.project_name}-ebs-csi-driver-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-ebs-csi-driver-role"
  })
}

# Attach AWS managed policy for EBS CSI driver
resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver.name
}

# EBS CSI Driver addon
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.ebs_csi_addon_version
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.ebs_csi_driver_policy
  ]

  tags = var.common_tags
}

# =============================================================================
# EFS CSI DRIVER CONFIGURATION
# =============================================================================

# IAM role for EFS CSI driver (conditional)
resource "aws_iam_role" "efs_csi_driver" {
  count = var.enable_efs_csi_driver ? 1 : 0
  
  name = "${var.project_name}-efs-csi-driver-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:efs-csi-controller-sa"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-efs-csi-driver-role"
  })
}

# Attach AWS managed policy for EFS CSI driver (conditional)
resource "aws_iam_role_policy_attachment" "efs_csi_driver_policy" {
  count = var.enable_efs_csi_driver ? 1 : 0
  
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  role       = aws_iam_role.efs_csi_driver[0].name
}

# EFS CSI Driver addon (conditional)
resource "aws_eks_addon" "efs_csi_driver" {
  count = var.enable_efs_csi_driver ? 1 : 0

  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-efs-csi-driver"
  addon_version            = var.efs_csi_addon_version
  service_account_role_arn = aws_iam_role.efs_csi_driver[0].arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.efs_csi_driver_policy
  ]

  tags = var.common_tags
}

# =============================================================================
# CSI SNAPSHOT CONTROLLER
# =============================================================================

# CSI Snapshot Controller addon (conditional, no IAM role required)
resource "aws_eks_addon" "snapshot_controller" {
  count = var.enable_snapshot_controller ? 1 : 0

  cluster_name      = aws_eks_cluster.main.name
  addon_name        = "snapshot-controller"
  addon_version     = var.snapshot_controller_addon_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.main
  ]

  tags = var.common_tags
}

# =============================================================================
# ENHANCED CLEANUP RESOURCES FOR RELIABLE DESTRUCTION
# =============================================================================

# Enhanced nodegroup cleanup with proper drainage
resource "null_resource" "nodegroup_cleanup" {
  triggers = {
    cluster_name    = aws_eks_cluster.main.name
    nodegroup_name  = aws_eks_node_group.main.node_group_name
    region          = var.aws_region
    profile         = var.aws_profile
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "=== Enhanced EKS Nodegroup Cleanup ==="
      
      # Try to drain nodes gracefully if kubectl is available
      if command -v kubectl >/dev/null 2>&1; then
        echo "Attempting to drain nodes gracefully..."
        kubectl get nodes --no-headers -o custom-columns=":metadata.name" 2>/dev/null | while read node; do
          if [ ! -z "$node" ]; then
            echo "Draining node: $node"
            kubectl drain $node --ignore-daemonsets --delete-emptydir-data --force --grace-period=30 --timeout=120s 2>/dev/null || true
          fi
        done
      else
        echo "kubectl not available, skipping node drainage"
      fi
      
      # Delete the nodegroup
      echo "Deleting EKS nodegroup: ${self.triggers.nodegroup_name}"
      aws eks delete-nodegroup \
        --cluster-name ${self.triggers.cluster_name} \
        --nodegroup-name ${self.triggers.nodegroup_name} \
        --region ${self.triggers.region} \
        --profile ${self.triggers.profile} || echo "Nodegroup already deleted"
      
      echo "Waiting for nodegroup deletion to complete..."
      aws eks wait nodegroup-deleted \
        --cluster-name ${self.triggers.cluster_name} \
        --nodegroup-name ${self.triggers.nodegroup_name} \
        --region ${self.triggers.region} \
        --profile ${self.triggers.profile} || echo "Nodegroup deletion completed"
      
      echo "Nodegroup cleanup completed successfully"
    EOT
  }

  depends_on = [aws_eks_node_group.main]
}

# Cleanup Lambda ENIs (for high-performance node groups)
resource "null_resource" "cleanup_lambda_enis" {
  triggers = {
    vpc_id  = var.vpc_id
    region  = var.aws_region
    profile = var.aws_profile
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "=== Lambda ENI Cleanup ==="
      
      # Find and delete Lambda-managed ENIs
      ENI_IDS=$(aws ec2 describe-network-interfaces \
        --filters "Name=vpc-id,Values=${self.triggers.vpc_id}" \
        --query 'NetworkInterfaces[?contains(Description, `AWS Lambda`) == `true`].NetworkInterfaceId' \
        --output text \
        --region ${self.triggers.region} \
        --profile ${self.triggers.profile} 2>/dev/null || echo "")
      
      if [ ! -z "$ENI_IDS" ]; then
        echo "Found Lambda ENIs to clean up: $ENI_IDS"
        for eni in $ENI_IDS; do
          if [ ! -z "$eni" ] && [ "$eni" != "None" ]; then
            echo "Deleting Lambda ENI: $eni"
            aws ec2 delete-network-interface \
              --network-interface-id $eni \
              --region ${self.triggers.region} \
              --profile ${self.triggers.profile} 2>/dev/null || echo "ENI $eni already deleted or detached"
          fi
        done
      else
        echo "No Lambda ENIs found for cleanup"
      fi
      
      echo "Lambda ENI cleanup completed"
    EOT
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main
  ]
}

# Cleanup remaining EKS and orphaned ENIs
resource "null_resource" "cleanup_eks_enis" {
  triggers = {
    vpc_id       = var.vpc_id
    cluster_name = aws_eks_cluster.main.name
    region       = var.aws_region
    profile      = var.aws_profile
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "=== EKS ENI Cleanup ==="
      
      # Wait a bit for EKS cleanup to complete
      echo "Waiting for EKS cluster cleanup..."
      sleep 30
      
      # Find and delete available (unattached) ENIs
      ENI_IDS=$(aws ec2 describe-network-interfaces \
        --filters "Name=vpc-id,Values=${self.triggers.vpc_id}" "Name=status,Values=available" \
        --query 'NetworkInterfaces[].NetworkInterfaceId' \
        --output text \
        --region ${self.triggers.region} \
        --profile ${self.triggers.profile} 2>/dev/null || echo "")
      
      if [ ! -z "$ENI_IDS" ]; then
        echo "Found available ENIs to clean up: $ENI_IDS"
        for eni in $ENI_IDS; do
          if [ ! -z "$eni" ] && [ "$eni" != "None" ]; then
            echo "Deleting available ENI: $eni"
            aws ec2 delete-network-interface \
              --network-interface-id $eni \
              --region ${self.triggers.region} \
              --profile ${self.triggers.profile} 2>/dev/null || echo "ENI $eni already deleted"
          fi
        done
      else
        echo "No available ENIs found for cleanup"
      fi
      
      echo "EKS ENI cleanup completed"
    EOT
  }

  depends_on = [
    null_resource.nodegroup_cleanup,
    null_resource.cleanup_lambda_enis
  ]
}