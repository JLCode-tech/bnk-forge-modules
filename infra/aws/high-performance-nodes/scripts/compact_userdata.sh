Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="
MIME-Version: 1.0

--==MYBOUNDARY==
Content-Type: text/cloud-boothook; charset="us-ascii"
#!/bin/bash
# Cloud boot hook - runs early in boot process
set -euo pipefail

# Create state directory
mkdir -p /var/lib/dpdk-setup/
echo "PHASE_1_STARTED" > /var/lib/dpdk-setup/phase1.state

--==MYBOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"
#!/bin/bash
set -euo pipefail

# ================================
# ROBUST DPDK USERDATA SCRIPT
# Based on AWS best practices
# ================================

# Configuration from Terraform
S3_BUCKET="${s3_bucket_name}"
REGION="${region}"
HUGEPAGES_2MI="${hugepages_2mi}"
HUGEPAGES_1GI="${hugepages_1gi}"
F5_SPK_ENABLED="${f5_spk_enabled}"
F5_TMM_CPU_CORES="${f5_tmm_cpu_cores}"
F5_NUMA_NODE="${f5_numa_node}"

# State management
STATE_DIR="/var/lib/dpdk-setup"
LOG_FILE="/var/log/dpdk-setup.log"
CHECKPOINT_FILE="$STATE_DIR/checkpoints"

# ================================
# LOGGING AND ERROR HANDLING
# ================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    echo "FAILED: $1" > "$STATE_DIR/error.state"
    # Send notification to CloudWatch
    aws logs put-log-events \
        --log-group-name "/aws/ec2/dpdk-setup" \
        --log-stream-name "$(hostname)" \
        --log-events timestamp=$(date +%s000),message="DPDK Setup Failed: $1" \
        --region "$REGION" 2>/dev/null || true
    exit 1
}

# Checkpoint system for resumability
checkpoint() {
    log "CHECKPOINT: $1"
    echo "$1:$(date +%s)" >> "$CHECKPOINT_FILE"
}

is_checkpoint_complete() {
    grep -q "^$1:" "$CHECKPOINT_FILE" 2>/dev/null
}

# Retry mechanism with exponential backoff
retry_with_backoff() {
    local max_attempts=5
    local attempt=1
    local delay=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Attempting: $* (attempt $attempt/$max_attempts)"
        if "$@"; then
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            error_exit "Failed after $max_attempts attempts: $*"
        fi
        
        log "Attempt $attempt failed, retrying in $${delay}s..."
        sleep $delay
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
}

# ================================
# INSTANCE METADATA
# ================================
get_metadata() {
    local path="$1"
    local token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    curl -s -H "X-aws-ec2-metadata-token: $token" \
        "http://169.254.169.254/latest/$path"
}

INSTANCE_ID=$(get_metadata "meta-data/instance-id")
AZ=$(get_metadata "meta-data/placement/availability-zone")

log "Starting robust DPDK setup - Instance: $INSTANCE_ID, AZ: $AZ"

# ================================
# PHASE 1: KERNEL PARAMETERS
# ================================
if ! is_checkpoint_complete "kernel_params"; then
    log "Phase 1: Configuring kernel parameters"
    
    # Check if hugepages already configured
    if grep -q "hugepagesz=2M" /proc/cmdline; then
        log "Hugepages already configured"
        NEEDS_REBOOT=false
    else
        log "Adding hugepages to kernel parameters"
        NEEDS_REBOOT=true
        
        cp /etc/default/grub /etc/default/grub.backup
        
        KERNEL_PARAMS="default_hugepagesz=2M hugepagesz=2M hugepages=$HUGEPAGES_2MI hugepagesz=1G hugepages=$HUGEPAGES_1GI intel_iommu=on iommu=pt"
        
        if [ "$F5_SPK_ENABLED" = "true" ]; then
            TOTAL_CPUS=$(nproc)
            if [ $TOTAL_CPUS -gt $F5_TMM_CPU_CORES ]; then
                ISOLATED_CPUS="$${F5_TMM_CPU_CORES}-$((TOTAL_CPUS-1))"
                KERNEL_PARAMS="$KERNEL_PARAMS isolcpus=$ISOLATED_CPUS nohz_full=$ISOLATED_CPUS rcu_nocbs=$ISOLATED_CPUS numa_balancing=disable"
            fi
        fi
        
        sed -i "s/biosdevname=0/& $KERNEL_PARAMS/g" /etc/default/grub
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
    
    checkpoint "kernel_params"
fi

# ================================
# PHASE 2: SYSTEM PACKAGES
# ================================
if ! is_checkpoint_complete "packages"; then
    log "Phase 2: Installing system packages"
    
    retry_with_backoff yum update -y
    retry_with_backoff yum install -y \
        net-tools pciutils wget curl awscli \
        kernel kernel-devel kernel-headers \
        git gcc make python3 python3-pip \
        numactl-devel libhugetlbfs-utils libpcap-devel
    
    checkpoint "packages"
fi

# ================================
# PHASE 3: NETWORK OPTIMIZATIONS
# ================================
if ! is_checkpoint_complete "network_opts"; then
    log "Phase 3: Applying network optimizations"
    
    cat << 'SYSCTL_EOF' >> /etc/sysctl.conf
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.tcp_rmem = 187380 655360 6291456
net.ipv4.udp_rmem_min = 1048576
net.ipv4.udp_wmem_min = 1048576
net.ipv6.conf.all.forwarding = 1
net.core.rmem_max = 268435456
net.core.wmem_max = 268435456
net.core.rmem_default = 67108864
net.core.wmem_default = 67108864
SYSCTL_EOF
    
    sysctl -p
    checkpoint "network_opts"
fi

# ================================
# PHASE 4: DPDK CONTINUATION SERVICE
# ================================
if ! is_checkpoint_complete "dpdk_service"; then
    log "Phase 4: Creating DPDK continuation service"
    
    # Download the main DPDK setup script from S3
    retry_with_backoff aws s3 cp "s3://$S3_BUCKET/dpdk-setup.sh" /usr/local/bin/dpdk-setup.sh --region "$REGION"
    chmod +x /usr/local/bin/dpdk-setup.sh
    
    # Create robust continuation service
    cat << 'DPDK_SERVICE_EOF' > /usr/lib/systemd/system/dpdk-continuation.service
[Unit]
Description=DPDK Setup Continuation Service
After=network-online.target
Wants=network-online.target
DefaultDependencies=false

[Service]
Type=oneshot
ExecStart=/usr/local/bin/dpdk-continuation.sh
RemainAfterExit=yes
TimeoutStartSec=1200
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
DPDK_SERVICE_EOF

    # Create the continuation script
    cat << CONTINUATION_SCRIPT > /usr/local/bin/dpdk-continuation.sh
#!/bin/bash
set -euo pipefail

log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a /var/log/dpdk-continuation.log
}

log "Starting DPDK continuation service"

# Wait for Lambda ENI attachment with robust checking
MAX_WAIT=600
WAIT_TIME=0
INTERFACE_TARGET=3

while [ \$WAIT_TIME -lt \$MAX_WAIT ]; do
    # Optimization: Use Bash glob expansion instead of ls | grep | wc
    shopt -s nullglob
    eth_interfaces=(/sys/class/net/eth[0-9]*)
    INTERFACE_COUNT=\${#eth_interfaces[@]}
    shopt -u nullglob
    log "Found \$INTERFACE_COUNT network interfaces (target: \$INTERFACE_TARGET)"
    
    if [ \$INTERFACE_COUNT -ge \$INTERFACE_TARGET ]; then
        log "All expected interfaces available, proceeding with DPDK setup"
        break
    fi
    
    # Check if Lambda failed (no new interfaces after 300s)
    if [ \$WAIT_TIME -gt 300 ] && [ \$INTERFACE_COUNT -lt 2 ]; then
        log "WARNING: Lambda ENI attachment may have failed, proceeding with available interfaces"
        break
    fi
    
    sleep 15
    WAIT_TIME=\$((WAIT_TIME + 15))
done

# Call the main DPDK setup script with parameters
/usr/local/bin/dpdk-setup.sh \\
    "$HUGEPAGES_2MI" \\
    "$HUGEPAGES_1GI" \\
    "$REGION" \\
    "$S3_BUCKET" \\
    "$F5_SPK_ENABLED" \\
    "$F5_TMM_CPU_CORES" \\
    "$F5_NUMA_NODE"

log "DPDK continuation completed successfully"
CONTINUATION_SCRIPT
    
    chmod +x /usr/local/bin/dpdk-continuation.sh
    systemctl enable dpdk-continuation.service
    
    checkpoint "dpdk_service"
fi

# ================================
# PHASE 5: NODE CONFIGURATION
# ================================
if ! is_checkpoint_complete "node_config"; then
    log "Phase 5: Creating node configuration"
    
    mkdir -p /etc/node-config
    
    cat << NODE_CONFIG_EOF > /etc/node-config/high-perf-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: node-config
data:
  hugepages_2mi: "$HUGEPAGES_2MI"
  hugepages_1gi: "$HUGEPAGES_1GI"  
  f5_spk_enabled: "$F5_SPK_ENABLED"
  f5_tmm_cpu_cores: "$F5_TMM_CPU_CORES"
  f5_numa_node: "$F5_NUMA_NODE"
  s3_bucket: "$S3_BUCKET"
  region: "$REGION"
  instance_id: "$INSTANCE_ID"
  dpdk_enabled: "true"
  sriov_enabled: "true"
NODE_CONFIG_EOF
    
    checkpoint "node_config"
fi

# ================================
# PHASE 6: HANDLE REBOOT OR CONTINUE
# ================================
if [ "$NEEDS_REBOOT" = "true" ]; then
    if ! is_checkpoint_complete "reboot_scheduled"; then
        log "Kernel parameters updated, scheduling reboot"
        
        # Create post-reboot validation
        cat << 'POST_REBOOT_EOF' > /usr/local/bin/post-reboot-validation.sh
#!/bin/bash
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/post-reboot.log
}

log "Post-reboot validation starting"

# Verify hugepages
HUGE_2M=$(grep HugePages_Total /proc/meminfo | grep 2048 | awk '{print $2}')
log "Hugepages 2M allocated: $HUGE_2M"

# Start DPDK continuation service
systemctl start dpdk-continuation.service

log "Post-reboot validation completed"
POST_REBOOT_EOF
        
        chmod +x /usr/local/bin/post-reboot-validation.sh
        echo "/usr/local/bin/post-reboot-validation.sh" >> /etc/rc.d/rc.local
        chmod +x /etc/rc.d/rc.local
        systemctl enable rc-local
        
        checkpoint "reboot_scheduled"
        
        # Schedule delayed reboot
        log "Rebooting in 60 seconds for hugepages"
        nohup bash -c 'sleep 60; reboot' &
    fi
else
    log "No reboot needed, starting DPDK continuation immediately"
    systemctl start dpdk-continuation.service &
fi

log "Robust DPDK userdata setup completed successfully"

--==MYBOUNDARY==--