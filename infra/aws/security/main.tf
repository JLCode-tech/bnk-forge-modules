# infrastructure-modules/foundation/security/main.tf
# Security module - SSH keys, Security Groups, IAM roles, Jumphost, OIDC Provider

# =============================================================================
# SSH KEY MANAGEMENT - Single key pair for all infrastructure
# =============================================================================

# Generate single key pair for entire project infrastructure
resource "tls_private_key" "infrastructure_key" {
  algorithm = var.ssh_key_algorithm
  rsa_bits  = var.ssh_key_rsa_bits
}

# Deploy public key to AWS (used by all EC2 instances)
resource "aws_key_pair" "infrastructure_key" {
  key_name   = "${var.project_name}-infrastructure-kp"
  public_key = tls_private_key.infrastructure_key.public_key_openssh
  
  tags = merge(var.common_tags, {
    Name = "${var.project_name}-infrastructure-kp"
  })
}

# Store private key locally for laptop access to jumphost
resource "local_sensitive_file" "private_key_local" {
  content         = tls_private_key.infrastructure_key.private_key_pem
  filename        = pathexpand("~/.ssh/${var.project_name}-infrastructure-kp.pem")
  file_permission = "0400"
}

# =============================================================================
# SECURITY GROUPS
# =============================================================================

# VPC Security Group with /32 IP restriction (easily updatable)
resource "aws_security_group" "vpc_sg" {
  name_prefix = "${var.project_name}-vpc-sg-"
  description = "Security group for all instances in VPC with /32 IP restriction"
  vpc_id      = var.vpc_id
  
  # SSH from your specific IP only (easily updatable)
  ingress {
    description = "SSH from authorized IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.user_ip]
  }
  
  # ICMP from anywhere (for network troubleshooting)
  ingress {
    description = "ICMP from anywhere"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # All traffic within VPC
  ingress {
    description = "All traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr_block]
  }
  
  # All egress traffic
  egress {
    description = "All egress traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc-sg"
  })
}

# =============================================================================
# ENHANCED JUMPHOST CONFIGURATION
# =============================================================================

# Data source for Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Primary jumphost network interface
resource "aws_network_interface" "jumphost_primary" {
  subnet_id         = var.public_subnet_id
  security_groups   = [aws_security_group.vpc_sg.id]
  source_dest_check = false
  
  tags = merge(var.common_tags, {
    Name = "${var.project_name}-jumphost-primary-eni"
  })
}

# Secondary jumphost network interface (for advanced networking)
resource "aws_network_interface" "jumphost_secondary" {
  subnet_id         = var.public_subnet_id
  security_groups   = [aws_security_group.vpc_sg.id]
  source_dest_check = false
  
  tags = merge(var.common_tags, {
    Name = "${var.project_name}-jumphost-secondary-eni"
  })
}

# Elastic IP for jumphost
resource "aws_eip" "jumphost" {
  domain = "vpc"
  
  tags = merge(var.common_tags, {
    Name = "${var.project_name}-jumphost-eip"
  })
}

# Associate EIP with jumphost primary interface
resource "aws_eip_association" "jumphost" {
  network_interface_id = aws_network_interface.jumphost_primary.id
  allocation_id        = aws_eip.jumphost.id
}

# Main jumphost instance
resource "aws_instance" "jumphost" {
  ami                  = data.aws_ami.amazon_linux.id
  instance_type        = var.jumphost_instance_type
  key_name             = aws_key_pair.infrastructure_key.key_name
  iam_instance_profile = aws_iam_instance_profile.jumphost_profile.name
  
  # Primary network interface
  network_interface {
    network_interface_id = aws_network_interface.jumphost_primary.id
    device_index         = 0
  }
  
  # Secondary network interface
  network_interface {
    network_interface_id = aws_network_interface.jumphost_secondary.id
    device_index         = 1
  }
  
  # Enhanced user data with SSH key deployment
  user_data = base64encode(templatefile("${path.module}/templates/jumphost_userdata.sh", {
    project_name        = var.project_name
    region             = var.aws_region
    sso_profile        = var.aws_profile
    kubectl_version    = var.kubectl_version
    kubectl_release_date = var.kubectl_release_date
  }))
  
  root_block_device {
    volume_size = var.jumphost_volume_size
    volume_type = "gp3"
    encrypted   = true
    delete_on_termination = true
    
    tags = merge(var.common_tags, {
      Name = "${var.project_name}-jumphost-root-volume"
    })
  }
  
  tags = merge(var.common_tags, {
    Name = "${var.project_name}-jumphost"
  })
}

# =============================================================================
# OPTIONAL BACKUP JUMPHOST (controlled by variable)
# =============================================================================

# Backup jumphost resources (conditional)
resource "aws_network_interface" "jumphost_backup_primary" {
  count = var.enable_jumphost_backup ? 1 : 0
  
  subnet_id         = var.public_subnet_id
  security_groups   = [aws_security_group.vpc_sg.id]
  source_dest_check = false
  
  tags = merge(var.common_tags, {
    Name = "${var.project_name}-jumphost-backup-primary-eni"
  })
}

resource "aws_network_interface" "jumphost_backup_secondary" {
  count = var.enable_jumphost_backup ? 1 : 0
  
  subnet_id         = var.public_subnet_id
  security_groups   = [aws_security_group.vpc_sg.id]
  source_dest_check = false
  
  tags = merge(var.common_tags, {
    Name = "${var.project_name}-jumphost-backup-secondary-eni"
  })
}

resource "aws_eip" "jumphost_backup" {
  count = var.enable_jumphost_backup ? 1 : 0
  
  domain = "vpc"
  
  tags = merge(var.common_tags, {
    Name = "${var.project_name}-jumphost-backup-eip"
  })
}

resource "aws_eip_association" "jumphost_backup" {
  count = var.enable_jumphost_backup ? 1 : 0
  
  network_interface_id = aws_network_interface.jumphost_backup_primary[0].id
  allocation_id        = aws_eip.jumphost_backup[0].id
}

resource "aws_instance" "jumphost_backup" {
  count = var.enable_jumphost_backup ? 1 : 0
  
  ami                  = data.aws_ami.amazon_linux.id
  instance_type        = var.jumphost_instance_type
  key_name             = aws_key_pair.infrastructure_key.key_name
  iam_instance_profile = aws_iam_instance_profile.jumphost_profile.name
  
  network_interface {
    network_interface_id = aws_network_interface.jumphost_backup_primary[0].id
    device_index         = 0
  }
  
  network_interface {
    network_interface_id = aws_network_interface.jumphost_backup_secondary[0].id
    device_index         = 1
  }
  
  user_data = base64encode(templatefile("${path.module}/templates/jumphost_userdata.sh", {
    project_name        = var.project_name
    region             = var.aws_region
    sso_profile        = var.aws_profile
    kubectl_version    = var.kubectl_version
    kubectl_release_date = var.kubectl_release_date
  }))
  
  root_block_device {
    volume_size = var.jumphost_volume_size
    volume_type = "gp3"
    encrypted   = true
    delete_on_termination = true
  }
  
  tags = merge(var.common_tags, {
    Name = "${var.project_name}-jumphost-backup"
  })
}