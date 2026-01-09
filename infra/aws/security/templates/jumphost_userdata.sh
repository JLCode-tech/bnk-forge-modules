#!/bin/bash
# infrastructure-modules/foundation/security/templates/jumphost_userdata.sh
# Enhanced jumphost user-data script with SSM, SSH keys, and variable kubectl version

set -e

# Log everything
exec > >(tee /var/log/jumphost-setup.log) 2>&1
echo "Starting jumphost setup at $(date)"
echo "Project: ${project_name}"
echo "Region: ${region}"
echo "kubectl version: ${kubectl_version}"

# Download with retry function
download_with_retry() {
    local url=$1
    local output=$2
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "Download attempt $attempt for $url"
        if curl -fsSL --connect-timeout 10 --max-time 300 "$url" -o "$output"; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 5
    done
    echo "Failed to download $url after $max_attempts attempts"
    return 1
}

# Update system
echo "Updating system packages..."
yum update -y

# Install basic tools
echo "Installing basic tools..."
yum install -y git docker unzip wget curl jq make socat

# Configure and start SSM Agent
echo "Configuring SSM Agent..."
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
systemctl status amazon-ssm-agent

# Create basic CloudWatch log group (minimal integration)
echo "Setting up basic CloudWatch logging..."
yum install -y amazon-cloudwatch-agent
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc

# Install kubectl with variable version
echo "Installing kubectl version ${kubectl_version}..."
download_with_retry "https://amazon-eks.s3.us-west-2.amazonaws.com/${kubectl_version}/${kubectl_release_date}/bin/linux/amd64/kubectl" "kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install AWS CLI v2
echo "Installing AWS CLI v2..."
download_with_retry "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install Helm
echo "Installing Helm..."
HELM_VERSION="v3.14.0"
curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz -o helm.tar.gz
tar -xzf helm.tar.gz
mv linux-amd64/helm /usr/local/bin/helm
rm -rf linux-amd64 helm.tar.gz
chmod +x /usr/local/bin/helm

# Install k9s (reliable method with version pinning)
echo "Installing k9s..."
K9S_VERSION="v0.32.4"
download_with_retry "https://github.com/derailed/k9s/releases/download/$K9S_VERSION/k9s_Linux_amd64.tar.gz" "k9s.tar.gz"
tar -xzf k9s.tar.gz
chmod +x k9s
mv k9s /usr/local/bin/
rm -f k9s.tar.gz

# Install yq
echo "Installing yq..."
YQ_VERSION="v4.50.1"
download_with_retry "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" "/usr/local/bin/yq"
chmod +x /usr/local/bin/yq

# Setup Docker
echo "Setting up Docker..."
systemctl enable docker
systemctl start docker
usermod -a -G docker ec2-user

# Create .kube directory for ec2-user
mkdir -p /home/ec2-user/.kube
chown ec2-user:ec2-user /home/ec2-user/.kube

# Create and setup SSH directory
echo "Setting up SSH configuration..."
mkdir -p /home/ec2-user/.ssh
chown ec2-user:ec2-user /home/ec2-user/.ssh
chmod 700 /home/ec2-user/.ssh

# SSH config for EKS node access (private IPs only)
# Note: Using SSH Agent Forwarding is recommended instead of storing private keys
cat > /home/ec2-user/.ssh/config << 'EOF'
Host eks-node-*
    User ec2-user
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host 10.*
    User ec2-user
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host 172.*
    User ec2-user
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
chmod 600 /home/ec2-user/.ssh/config
chown ec2-user:ec2-user /home/ec2-user/.ssh/config

# Setup kubectl config script
echo "Creating kubectl config script..."
cat > /home/ec2-user/configure-kubectl.sh << 'EOF'
#!/bin/bash
echo "Configuring kubectl for EKS cluster..."
aws eks update-kubeconfig --region ${region} --name ${project_name}-cluster --profile ${sso_profile}
echo "kubectl configured successfully"
echo "Cluster info:"
kubectl cluster-info
echo ""
echo "Available nodes:"
kubectl get nodes
EOF

chmod +x /home/ec2-user/configure-kubectl.sh
chown ec2-user:ec2-user /home/ec2-user/configure-kubectl.sh

# Create useful aliases and bashrc additions
echo "Setting up user environment..."
cat >> /home/ec2-user/.bashrc << 'EOF'

# EKS and kubectl aliases
alias k='kubectl'
alias kgn='kubectl get nodes'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgns='kubectl get namespaces'
alias kdp='kubectl describe pod'
alias kdn='kubectl describe node'

# SSH aliases for EKS nodes
alias ssh-eks='ssh ec2-user@'

# Useful functions
kexec() {
    kubectl exec -it $1 -- /bin/bash
}

klogs() {
    kubectl logs -f $1
}

# Set kubectl autocompletion
source <(kubectl completion bash)
complete -F __start_kubectl k
EOF

# Set proper ownership for bashrc
chown ec2-user:ec2-user /home/ec2-user/.bashrc

# Create welcome message
cat > /home/ec2-user/README.md << 'EOF'
# ${project_name} Jumphost

## Quick Start
```bash
# Configure kubectl access to EKS cluster
./configure-kubectl.sh

# Test cluster access
kubectl get nodes
kubectl get pods --all-namespaces

# Access EKS nodes via SSH (private IPs only)
# USE SSH AGENT FORWARDING: ssh -A -i <key> ec2-user@<jumphost-ip>
# First get node IPs: kubectl get nodes -o wide
ssh eks-node-10.0.1.100  # Example IP
# or use: ssh-eks 10.0.1.100
```

## Available Tools
- AWS CLI v2
- kubectl ${kubectl_version}
- Helm 3
- k9s (Kubernetes UI)
- Docker
- yq, jq
- git, make

## Useful Aliases
- `k` = kubectl
- `kgn` = kubectl get nodes
- `kgp` = kubectl get pods
- `ssh-eks` = SSH to EKS nodes

## Log Files
- Setup log: `/var/log/jumphost-setup.log`
- SSM Agent: `journalctl -u amazon-ssm-agent`

## Security
- SSH access to EKS nodes via private IPs only
- No direct public access to EKS nodes
- SSM Session Manager enabled for secure access
EOF

chown ec2-user:ec2-user /home/ec2-user/README.md

# Verify installations
echo "Verifying tool installations..."
kubectl version --client || echo "kubectl install failed"
aws --version || echo "AWS CLI install failed"
helm version || echo "helm install failed"
k9s version || echo "k9s install failed"
jq --version || echo "jq install failed"
yq --version || echo "yq install failed"
docker --version || echo "docker install failed"

# Verify SSM Agent
systemctl is-active amazon-ssm-agent || echo "SSM Agent not running"

# Final status
echo "========================================="
echo "Jumphost setup completed successfully at $(date)"
echo "Project: ${project_name}"
echo "Region: ${region}"
echo "kubectl version: ${kubectl_version}"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. SSH to jumphost: ssh -i ~/.ssh/${project_name}-infrastructure-kp.pem ec2-user@<jumphost-ip>"
echo "2. Configure kubectl: ./configure-kubectl.sh"
echo "3. Access EKS cluster: kubectl get nodes"
echo "========================================="