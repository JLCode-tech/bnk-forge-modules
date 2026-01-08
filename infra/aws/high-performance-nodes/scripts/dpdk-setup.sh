#!/bin/bash
set -o xtrace

# Parameters from userdata
HUGEPAGES_2MI=${1:-4096}  # Updated default for F5 SPK (8Gi)
HUGEPAGES_1GI=${2:-2}
REGION=${3:-us-west-2}
S3_BUCKET=${4}
F5_SPK_ENABLED=${5:-false}
F5_TMM_CPU_CORES=${6:-4}
F5_NUMA_NODE=${7:-0}

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/dpdk-setup.log
}

log "Starting enhanced DPDK setup with F5 SPK support"
log "Parameters: hugepages_2mi=$HUGEPAGES_2MI, hugepages_1gi=$HUGEPAGES_1GI, region=$REGION"
log "F5 SPK: enabled=$F5_SPK_ENABLED, cpu_cores=$F5_TMM_CPU_CORES, numa_node=$F5_NUMA_NODE"

# Error handling
err_report() {
    log "Exited with error on line $1"
}
trap 'err_report $LINENO' ERR

# =======================
# DPDK INSTALLATION
# =======================
log "Installing DPDK packages and dependencies"

# Update system and install packages
yum update -y
yum install -y net-tools pciutils numactl-devel libhugetlbfs-utils libpcap-devel \
    kernel kernel-devel kernel-headers git gcc make wget python3 python3-pip \
    htop iotop sysstat perf

# Install additional packages for F5 SPK if enabled
if [ "$F5_SPK_ENABLED" = "true" ]; then
    log "Installing F5 SPK specific packages"
    yum install -y tuned tuned-utils irqbalance
    
    # Install performance tuning profile
    tuned-adm profile network-latency
fi

# Clone Amazon drivers
log "Cloning Amazon drivers repository"
cd /opt
git clone https://github.com/amzn/amzn-drivers.git

# Run VFIO patch script from cloned repo (avoids redundant downloads)
log "Setting up VFIO patches"
cd /opt/amzn-drivers/userspace/dpdk/enav2-vfio-patch/
chmod +x get-vfio-with-wc.sh
./get-vfio-with-wc.sh
cd /

# Create DPDK directory and download scripts from S3
log "Setting up DPDK directory and downloading scripts from S3"
mkdir -p /opt/dpdk/

# Download DPDK scripts from S3 (in parallel)
pids=""
aws s3 cp s3://$S3_BUCKET/dpdk-devbind.py /opt/dpdk/dpdk-devbind.py --region $REGION &
pids="$pids $!"
aws s3 cp s3://$S3_BUCKET/sriov-init.sh /opt/dpdk/sriov-init.sh --region $REGION &
pids="$pids $!"
aws s3 cp s3://$S3_BUCKET/config-sriov.sh /opt/dpdk/config-sriov.sh --region $REGION &
pids="$pids $!"
aws s3 cp s3://$S3_BUCKET/dpdk-resource-builder.py /opt/dpdk/dpdk-resource-builder.py --region $REGION &
pids="$pids $!"

for pid in $pids; do
    wait $pid || { log "Failed to download DPDK scripts"; exit 1; }
done

# Download new SR-IOV CNI installer script
aws s3 cp s3://$S3_BUCKET/install-sriov-cni.sh /opt/dpdk/install-sriov-cni.sh --region $REGION 2>/dev/null || {
    log "Creating SR-IOV CNI installer script locally"
    cat << 'SRIOV_CNI_INSTALLER' > /opt/dpdk/install-sriov-cni.sh
#!/bin/bash
# Install SR-IOV CNI binary locally as fallback

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/sriov-cni-install.log
}

log "Installing SR-IOV CNI binary to /opt/cni/bin/"

# Create CNI bin directory if it doesn't exist
mkdir -p /opt/cni/bin/

# Download and install SR-IOV CNI binary
cd /tmp
wget -q https://github.com/k8snetworkplumbingwg/sriov-cni/releases/latest/download/sriov-cni-amd64.tgz
tar -xzf sriov-cni-amd64.tgz
cp sriov /opt/cni/bin/
chmod +x /opt/cni/bin/sriov

# Verify installation
if [ -f "/opt/cni/bin/sriov" ]; then
    log "SR-IOV CNI binary installed successfully"
    ls -la /opt/cni/bin/sriov
else
    log "ERROR: SR-IOV CNI binary installation failed"
    exit 1
fi

# Cleanup
rm -f /tmp/sriov-cni-amd64.tgz /tmp/sriov
SRIOV_CNI_INSTALLER
}

chmod +x /opt/dpdk/*.sh /opt/dpdk/*.py

# Download systemd service files from S3 (in parallel)
pids=""
aws s3 cp s3://$S3_BUCKET/sriov-init.service /usr/lib/systemd/system/sriov-init.service --region $REGION &
pids="$pids $!"
aws s3 cp s3://$S3_BUCKET/config-sriov.service /usr/lib/systemd/system/config-sriov.service --region $REGION &
pids="$pids $!"

for pid in $pids; do
    wait $pid || { log "Failed to download service files"; exit 1; }
done

# Install SR-IOV CNI binary
log "Installing SR-IOV CNI binary"
/opt/dpdk/install-sriov-cni.sh

# =======================
# HUGEPAGES CONFIGURATION
# =======================
log "Configuring hugepages: 2Mi=$HUGEPAGES_2MI (${HUGEPAGES_2MI}*2Mi = $((HUGEPAGES_2MI*2))Mi), 1Gi=$HUGEPAGES_1GI"

CURRENT_CMDLINE=$(cat /proc/cmdline)
if echo "$CURRENT_CMDLINE" | grep -q "hugepagesz=2M"; then
    log "Hugepages already configured"
    HUGEPAGES_CONFIGURED=true
else
    log "Configuring hugepages in GRUB"
    HUGEPAGES_CONFIGURED=false
    
    cp /etc/default/grub /etc/default/grub.backup
    
    # Enhanced hugepages configuration for F5 SPK
    if [ "$F5_SPK_ENABLED" = "true" ]; then
        HUGEPAGES_PARAMS="default_hugepagesz=2M hugepagesz=2M hugepages=$HUGEPAGES_2MI hugepagesz=1G hugepages=$HUGEPAGES_1GI intel_iommu=on iommu=pt numa_balancing=disable"
    else
        HUGEPAGES_PARAMS="default_hugepagesz=2M hugepagesz=2M hugepages=$HUGEPAGES_2MI hugepagesz=1G hugepages=$HUGEPAGES_1GI intel_iommu=on iommu=pt"
    fi
    
    if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub; then
        sed -i 's/hugepagesz=[^ ]* hugepages=[^ ]*//g' /etc/default/grub
        sed -i 's/default_hugepagesz=[^ ]*//g' /etc/default/grub
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\([^\"]*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $HUGEPAGES_PARAMS\"/" /etc/default/grub
    else
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$HUGEPAGES_PARAMS\"" >> /etc/default/grub
    fi
    
    grub2-mkconfig -o /boot/grub2/grub.cfg
fi

# Set hugepages for current session
echo $HUGEPAGES_2MI > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || true

# =======================
# F5 SPK SPECIFIC CONFIGURATION
# =======================
if [ "$F5_SPK_ENABLED" = "true" ]; then
    log "Applying F5 SPK specific configurations"
    
    # Create F5 SPK directories
    mkdir -p /etc/f5-spk/
    mkdir -p /var/log/f5-spk/
    
    # F5 SPK hugepages verification
    log "F5 SPK hugepages verification: Total 2Mi pages requested: $HUGEPAGES_2MI ($(($HUGEPAGES_2MI * 2))Mi = $(($HUGEPAGES_2MI * 2 / 1024))Gi)"
    
    # F5 SPK specific NUMA configuration
    cat << F5_NUMA_CONFIG > /etc/f5-spk/numa-config.conf
# F5 SPK NUMA Configuration
NUMA_NODE=$F5_NUMA_NODE
TMM_CPU_CORES=$F5_TMM_CPU_CORES
HUGEPAGES_2MI=$HUGEPAGES_2MI
HUGEPAGES_1GI=$HUGEPAGES_1GI
F5_NUMA_CONFIG
    
    # IRQ affinity optimization for F5 SPK
    cat << 'F5_IRQ_SCRIPT' > /usr/local/bin/f5-spk-irq-optimization.sh
#!/bin/bash
# F5 SPK IRQ optimization script

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/f5-spk/irq-optimization.log
}

# Source F5 SPK configuration
if [ -f /etc/f5-spk/numa-config.conf ]; then
    source /etc/f5-spk/numa-config.conf
else
    log "F5 SPK NUMA configuration not found"
    exit 1
fi

log "Starting F5 SPK IRQ optimization for NUMA node $NUMA_NODE"

# Optimize IRQ affinity setting
# Performance Improvement: Replaced broken O(N*M) nested loops and fixed glob syntax error
# that prevented execution. New implementation uses awk for single-pass O(K) processing
# of /proc/interrupts to target only relevant network IRQs.
log "Applying IRQ affinity settings..."

# Define affinity mask based on NUMA node
# If NUMA_NODE is 0, we use mask 0f. Otherwise (node 1), we use f0.
AFFINITY_MASK="0f"
if [ "$NUMA_NODE" != "0" ]; then
    AFFINITY_MASK="f0"
fi

if [ -f /proc/interrupts ]; then
    # Parse /proc/interrupts to find IRQs associated with 'eth' interfaces
    # and set their affinity directly.
    awk -v mask="$AFFINITY_MASK" '
        /eth/ {
            # Extract IRQ number (first field, usually ends with :)
            irq = $1
            sub(":", "", irq)

            # Verify it is a number
            if (irq ~ /^[0-9]+$/) {
                # Construct path
                affinity_file = "/proc/irq/" irq "/smp_affinity"

                # Print command to be executed (or execute via system if safe, but generating commands is safer/easier to debug)
                print "echo " mask " > " affinity_file
            }
        }
    ' /proc/interrupts | while read -r cmd; do
        # Execute the generated command
        # We suppress errors because some IRQs might not be modifiable or gone
        eval "$cmd" 2>/dev/null || true
    done
else
    log "WARNING: /proc/interrupts not found, skipping IRQ optimization"
fi

log "F5 SPK IRQ optimization completed"
F5_IRQ_SCRIPT
    
    chmod +x /usr/local/bin/f5-spk-irq-optimization.sh
    
    # Create F5 SPK systemd service
    cat << F5_SERVICE > /usr/lib/systemd/system/f5-spk-optimization.service
[Unit]
Description=F5 SPK Performance Optimization
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/f5-spk-irq-optimization.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
F5_SERVICE
    
    systemctl enable f5-spk-optimization.service
fi

# =======================
# NETWORK CONFIGURATION
# =======================
log "Configuring network settings"

# Enhanced network optimizations for F5 SPK
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
net.core.netdev_max_backlog = 30000
net.core.netdev_budget = 600
SYSCTL_EOF

sysctl -p

# Wait for Lambda ENI attachment (up to 300 seconds)
log "Waiting for Lambda ENI attachment"
MAX_WAIT=300
WAIT_TIME=0
while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    INTERFACE_COUNT=$(ls /sys/class/net/ | grep -E '^eth[0-9]+$' | wc -l)
    log "Found $INTERFACE_COUNT network interfaces"
    
    if [ $INTERFACE_COUNT -ge 3 ]; then
        log "All expected interfaces available"
        break
    fi
    
    sleep 10
    WAIT_TIME=$((WAIT_TIME + 10))
done

# Bring up interfaces
for interface in $(ls /sys/class/net/ | grep eth); do
    log "Bringing up interface: $interface"
    ip link set $interface up 2>/dev/null || true
    echo "ifconfig $interface up" >> /etc/rc.d/rc.local
done

# =======================
# HUGEPAGES MOUNT POINTS
# =======================
log "Setting up hugepages mount points"
mkdir -p /mnt/huge-2m /mnt/huge-1g

if ! grep -q "/mnt/huge-2m" /etc/fstab; then
    echo "nodev /mnt/huge-2m hugetlbfs pagesize=2M 0 0" >> /etc/fstab
fi
if ! grep -q "/mnt/huge-1g" /etc/fstab; then
    echo "nodev /mnt/huge-1g hugetlbfs pagesize=1G 0 0" >> /etc/fstab
fi

# =======================
# PERFORMANCE OPTIMIZATIONS
# =======================
log "Applying performance optimizations"

# Disable transparent hugepages
echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo never > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true

# Add to rc.local
cat << 'PERF_SCRIPT' >> /etc/rc.d/rc.local
echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo never > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true

if ! mountpoint -q /mnt/huge-2m; then
    mount -t hugetlbfs -o pagesize=2M nodev /mnt/huge-2m 2>/dev/null || true
fi
if ! mountpoint -q /mnt/huge-1g; then
    mount -t hugetlbfs -o pagesize=1G nodev /mnt/huge-1g 2>/dev/null || true
fi

# F5 SPK specific optimizations
if [ -f /usr/local/bin/f5-spk-irq-optimization.sh ]; then
    /usr/local/bin/f5-spk-irq-optimization.sh
fi
PERF_SCRIPT

systemctl enable rc-local
chmod +x /etc/rc.d/rc.local

# Create enhanced verification script
cat << 'VERIFY_SCRIPT' > /usr/local/bin/verify-dpdk-setup.sh
#!/bin/bash
echo "=== Enhanced DPDK High-Performance Node Verification ==="
echo "Date: $(date)"
echo
echo "=== F5 SPK Configuration ==="
if [ -f /etc/f5-spk/numa-config.conf ]; then
    cat /etc/f5-spk/numa-config.conf
else
    echo "F5 SPK not configured"
fi
echo
echo "=== Hugepages Status ==="
grep -i huge /proc/meminfo
echo "Expected 2Mi hugepages: $HUGEPAGES_2MI (Total: $(($HUGEPAGES_2MI * 2))Mi = $(($HUGEPAGES_2MI * 2 / 1024))Gi)"
echo
echo "=== SR-IOV CNI Binary ==="
ls -la /opt/cni/bin/sriov 2>/dev/null || echo "SR-IOV CNI binary not found"
echo
echo "=== Network Interfaces ==="
ip link show | grep -E '^[0-9]+:' | awk '{print $2}' | tr -d ':'
echo
echo "=== PCI Devices ==="
lspci -d 1d0f: || echo "No ENA devices found"
echo
echo "=== DPDK Device Binding Status ==="
/opt/dpdk/dpdk-devbind.py --status 2>/dev/null || echo "DPDK devbind not available"
echo
echo "=== SR-IOV Configuration ==="
[ -f /etc/pcidp/config.json ] && cat /etc/pcidp/config.json || echo "No SR-IOV config found"
echo
echo "=== CPU Information ==="
lscpu | grep -E "(CPU\(s\)|NUMA node|Model name)"
echo
echo "=== F5 SPK Verification Commands ==="
echo "kubectl get nodes -l f5.com/spk-node=true"
echo "kubectl get nodes -l spk=tmm"
echo "kubectl describe nodes -l node-type=high-performance | grep -A10 -B10 hugepages"
VERIFY_SCRIPT

chmod +x /usr/local/bin/verify-dpdk-setup.sh

# Enable and start services
systemctl enable sriov-init.service
systemctl enable config-sriov.service
systemctl start sriov-init.service

# Handle reboot if needed
if [ "$HUGEPAGES_CONFIGURED" = "false" ]; then
    log "Scheduling reboot for hugepages configuration"
    
    cat << 'POST_REBOOT_SCRIPT' > /usr/local/bin/post-reboot-verification.sh
#!/bin/bash
sleep 30
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Post-reboot verification" >> /var/log/dpdk-setup.log
/usr/local/bin/verify-dpdk-setup.sh >> /var/log/dpdk-setup.log
systemctl start config-sriov.service
if [ -f /usr/lib/systemd/system/f5-spk-optimization.service ]; then
    systemctl start f5-spk-optimization.service
fi
POST_REBOOT_SCRIPT
    
    chmod +x /usr/local/bin/post-reboot-verification.sh
    echo "/usr/local/bin/post-reboot-verification.sh" >> /etc/rc.d/rc.local
    
    # Reboot after 60 seconds
    nohup bash -c 'sleep 60; reboot' &
else
    log "Starting services without reboot"
    systemctl start config-sriov.service
    if [ -f /usr/lib/systemd/system/f5-spk-optimization.service ]; then
        systemctl start f5-spk-optimization.service
    fi
    /usr/local/bin/verify-dpdk-setup.sh >> /var/log/dpdk-setup.log
fi

log "Enhanced DPDK setup with F5 SPK support completed"