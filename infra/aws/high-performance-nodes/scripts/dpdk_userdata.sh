Content-Type: multipart/mixed; boundary="==BOUNDARY=="
MIME-Version: 1.0

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"
#!/bin/bash
set -o xtrace

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/high-perf-setup.log
}

log "Starting DPDK-enabled high-performance node setup"

# Set kubelet extra arguments
cat << KUBELET_EOF > /etc/systemd/system/kubelet.service.d/90-kubelet-extra-args.conf
[Service]
Environment='USERDATA_EXTRA_ARGS=${kubelet_extra_args}'
KUBELET_EOF

# Update kubelet service files for EKS 1.24+
sed -i 's/KUBELET_EXTRA_ARGS/KUBELET_EXTRA_ARGS $USERDATA_EXTRA_ARGS/' /etc/systemd/system/kubelet.service 2>/dev/null || true
sed -i 's/KUBELET_EXTRA_ARGS/KUBELET_EXTRA_ARGS $USERDATA_EXTRA_ARGS/' /etc/eks/containerd/kubelet-containerd.service 2>/dev/null || true

# Get metadata for dynamic configuration
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
if [ -z "$Region" ]; then
  Region=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/dynamic/instance-identity/document | grep -oP '\"region\"[[:space:]]*:[[:space:]]*\"\K[^\"]+')
fi

log "Detected region: $Region"

# Error handling function
err_report() {
    log "Exited with error on line $1"
}
trap 'err_report $LINENO' ERR

# =======================
# DPDK INSTALLATION START
# =======================
log "Installing DPDK packages and dependencies"

# Update system
yum update -y

# Install essential packages for DPDK
yum install -y \
    net-tools \
    pciutils \
    numactl-devel \
    libhugetlbfs-utils \
    libpcap-devel \
    kernel \
    kernel-devel \
    kernel-headers \
    git \
    gcc \
    make \
    wget

log "Essential packages installed successfully"

# Clone Amazon drivers for ENA DPDK support
log "Cloning Amazon drivers repository"
cd /opt
git clone https://github.com/amzn/amzn-drivers.git
cd amzn-drivers
# Sentinel: Pin to specific commit to prevent supply chain attacks (2024-05-23)
git checkout 46e50d6265ef6669877610549205973955748039
cd ..

# Run VFIO patch script from cloned repo (avoids redundant downloads)
log "Setting up VFIO with write-combining patches"
cd /opt/amzn-drivers/userspace/dpdk/enav2-vfio-patch/
chmod +x get-vfio-with-wc.sh
./get-vfio-with-wc.sh
cd /

# Create DPDK directory structure
log "Setting up DPDK directory structure"
mkdir -p /opt/dpdk/

# Create a simple dpdk-devbind.py script (embedded version)
cat << 'DPDK_DEVBIND_EOF' > /opt/dpdk/dpdk-devbind.py
#!/usr/bin/env python3
# Simple DPDK device binding script for ENA interfaces
import subprocess
import sys
import os

def run_cmd(cmd):
    """Run shell command and return output"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.returncode, result.stdout, result.stderr
    except Exception as e:
        return 1, "", str(e)

def get_ena_devices():
    """Get list of ENA network devices"""
    ret, out, err = run_cmd("lspci -d 1d0f: -s 00:06.0,00:07.0")
    devices = []
    for line in out.strip().split('\n'):
        if line and 'Ethernet' in line:
            pci_addr = line.split()[0]
            devices.append(f"0000:{pci_addr}")
    return devices

def bind_device(pci_addr, driver):
    """Bind PCI device to specified driver"""
    print(f"Binding {pci_addr} to {driver}")
    
    # Unbind from current driver if bound
    run_cmd(f"echo {pci_addr} > /sys/bus/pci/devices/{pci_addr}/driver/unbind 2>/dev/null || true")
    
    # Bind to new driver
    if driver == "vfio-pci":
        # Enable VFIO
        run_cmd("modprobe vfio-pci")
        run_cmd(f"echo '1d0f ec20' > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true")
    
    run_cmd(f"echo {pci_addr} > /sys/bus/pci/drivers/{driver}/bind 2>/dev/null || true")

def show_status():
    """Show device binding status"""
    print("Network devices using kernel driver")
    print("===================================")
    devices = get_ena_devices()
    for dev in devices:
        ret, out, err = run_cmd(f"readlink /sys/bus/pci/devices/{dev}/driver 2>/dev/null")
        driver = out.strip().split('/')[-1] if out.strip() else "none"
        print(f"{dev} '{driver}'")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        show_status()
    elif sys.argv[1] == "--status":
        show_status()
    elif sys.argv[1] == "--bind":
        if len(sys.argv) != 4:
            print("Usage: dpdk-devbind.py --bind <driver> <pci_addr>")
            sys.exit(1)
        bind_device(sys.argv[3], sys.argv[2])
    else:
        show_status()
DPDK_DEVBIND_EOF

chmod +x /opt/dpdk/dpdk-devbind.py

# Create SR-IOV initialization script
log "Creating SR-IOV initialization script"
cat << 'SRIOV_INIT_EOF' > /opt/dpdk/sriov-init.sh
#!/bin/bash
# SR-IOV initialization script

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/sriov-init.log
}

log "Starting SR-IOV initialization"

# Wait for network interfaces to be available
sleep 10

# Check available network interfaces
log "Available network interfaces:"
ls -la /sys/class/net/ | tee -a /var/log/sriov-init.log

# Check PCI devices
log "ENA PCI devices:"
lspci -d 1d0f: | tee -a /var/log/sriov-init.log

# Bring up all ethernet interfaces
for iface in $(ls /sys/class/net/ | grep eth); do
    if [ -d "/sys/class/net/$iface" ]; then
        log "Bringing up interface: $iface"
        ip link set $iface up || true
    fi
done

log "SR-IOV initialization completed"
SRIOV_INIT_EOF

chmod +x /opt/dpdk/sriov-init.sh

# Create systemd service for SR-IOV initialization
cat << 'SRIOV_SERVICE_EOF' > /usr/lib/systemd/system/sriov-init.service
[Unit]
Description=SR-IOV Interface Initialization
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/dpdk/sriov-init.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SRIOV_SERVICE_EOF

# Create DPDK resource builder script
cat << 'DPDK_RESOURCE_EOF' > /opt/dpdk/dpdk-resource-builder.py
#!/usr/bin/env python3
# DPDK resource configuration builder

import json
import sys

def create_sriov_config(starting_interface=2, subnet_count=2):
    """Create SR-IOV device plugin configuration"""
    
    # Base configuration for SR-IOV device plugin
    config = {
        "resourceList": [
            {
                "resourceName": "internal_netdevice",
                "selectors": {
                    "vendors": ["1d0f"],
                    "devices": ["ec20"],
                    "drivers": ["ena", "vfio-pci"],
                    "pciAddresses": ["0000:00:06.0"]
                }
            },
            {
                "resourceName": "external_netdevice", 
                "selectors": {
                    "vendors": ["1d0f"],
                    "devices": ["ec20"],
                    "drivers": ["ena", "vfio-pci"],
                    "pciAddresses": ["0000:00:07.0"]
                }
            }
        ]
    }
    
    return config

if __name__ == "__main__":
    starting_interface = int(sys.argv[1]) if len(sys.argv) > 1 else 2
    subnet_count = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    
    config = create_sriov_config(starting_interface, subnet_count)
    
    # Write to temporary file
    with open('/tmp/data.txt', 'w') as f:
        json.dump(config, f, indent=2)
    
    print("SR-IOV configuration created successfully")
DPDK_RESOURCE_EOF

chmod +x /opt/dpdk/dpdk-resource-builder.py

# Create configuration service script  
cat << 'CONFIG_SRIOV_EOF' > /opt/dpdk/config-sriov.sh
#!/bin/bash
# Configure SR-IOV after ENI attachment

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/config-sriov.log
}

log "Starting SR-IOV configuration"

# Wait for Lambda ENI attachment (expect 3 total interfaces)
MAX_WAIT=300
WAIT_TIME=0
while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    INTERFACE_COUNT=$(ls /sys/class/net/ | grep -E '^eth[0-9]+$' | wc -l)
    log "Found $INTERFACE_COUNT network interfaces"
    
    if [ $INTERFACE_COUNT -ge 3 ]; then
        log "All expected interfaces available, proceeding with configuration"
        break
    fi
    
    sleep 10
    WAIT_TIME=$((WAIT_TIME + 10))
done

# Run DPDK resource builder
python3 /opt/dpdk/dpdk-resource-builder.py 2 2

# Create SR-IOV device plugin config directory
if [ -d "/etc/pcidp/" ]; then
    rm -rf /etc/pcidp/
fi
mkdir -p /etc/pcidp/

# Copy configuration files
cp /tmp/data.txt /etc/pcidp/config.json
cp /tmp/data.txt /var/config.json

log "SR-IOV configuration completed"
CONFIG_SRIOV_EOF

chmod +x /opt/dpdk/config-sriov.sh

# Create systemd service for SR-IOV configuration
cat << 'CONFIG_SERVICE_EOF' > /usr/lib/systemd/system/config-sriov.service
[Unit]
Description=Configure SR-IOV Resources
After=sriov-init.service

[Service]
Type=oneshot
ExecStart=/opt/dpdk/config-sriov.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
CONFIG_SERVICE_EOF

# Enable and start SR-IOV services
systemctl enable sriov-init.service
systemctl enable config-sriov.service

# ======================
# HUGEPAGES CONFIGURATION
# ======================
log "Configuring hugepages kernel parameters"

# Get current kernel command line
CURRENT_CMDLINE=$(cat /proc/cmdline)
log "Current kernel cmdline: $CURRENT_CMDLINE"

# Check if hugepages are already configured
if echo "$CURRENT_CMDLINE" | grep -q "hugepagesz=2M"; then
    log "Hugepages already configured in kernel, skipping reboot"
    HUGEPAGES_CONFIGURED=true
else
    log "Configuring hugepages in GRUB"
    HUGEPAGES_CONFIGURED=false
    
    # Backup original GRUB config
    cp /etc/default/grub /etc/default/grub.backup
    
    # Add hugepages to kernel command line (CloudFormation style)
    HUGEPAGES_PARAMS="default_hugepagesz=2Mi hugepagesz=2Mi hugepages=${hugepages_2mi} hugepagesz=1Gi hugepages=${hugepages_1gi} intel_iommu=on iommu=pt"
    
    # Update GRUB_CMDLINE_LINUX_DEFAULT
    if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub; then
        # Remove existing hugepages parameters if any
        sed -i 's/hugepagesz=[^ ]* hugepages=[^ ]*//g' /etc/default/grub
        sed -i 's/default_hugepagesz=[^ ]*//g' /etc/default/grub
        
        # Add new hugepages parameters
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\([^\"]*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $HUGEPAGES_PARAMS\"/" /etc/default/grub
    else
        # Add the line if it doesn't exist
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$HUGEPAGES_PARAMS\"" >> /etc/default/grub
    fi
    
    log "Updated GRUB configuration:"
    grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub | tee -a /var/log/high-perf-setup.log
    
    # Update GRUB
    log "Updating GRUB bootloader"
    grub2-mkconfig -o /boot/grub2/grub.cfg
fi

# Set hugepages for current session (before reboot)
echo ${hugepages_2mi} > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || true

# =======================
# NETWORK CONFIGURATION
# =======================
log "Configuring network settings"

# Network performance optimizations (from CloudFormation)
cat << 'SYSCTL_EOF' >> /etc/sysctl.conf
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.tcp_rmem = 187380 655360 6291456
net.ipv4.udp_rmem_min = 1048576
net.ipv4.udp_wmem_min = 1048576
net.ipv6.conf.all.forwarding = 1
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
SYSCTL_EOF

sysctl -p

# Function to discover and configure network interfaces (keep Lambda ENI attachment logic)
discover_and_configure_interfaces() {
    local max_wait=300
    local wait_time=0
    local check_interval=10
    
    log "Starting network interface discovery and configuration"
    
    while [ $wait_time -lt $max_wait ]; do
        current_interfaces=$(ls /sys/class/net/ 2>/dev/null | grep -E '^eth[0-9]+$' | sort)
        interface_count=$(echo "$current_interfaces" | wc -w)
        
        log "Found $interface_count network interfaces: $current_interfaces"
        
        # Bring up all discovered interfaces
        for interface in $current_interfaces; do
            if [ -d "/sys/class/net/$interface" ]; then
                log "Configuring interface: $interface"
                ip link set $interface up 2>/dev/null || ifconfig $interface up 2>/dev/null || true
                
                # Add to rc.local for persistence
                if ! grep -q "ifconfig $interface up" /etc/rc.d/rc.local 2>/dev/null; then
                    echo "ifconfig $interface up" >> /etc/rc.d/rc.local
                fi
            fi
        done
        
        # For Lambda ENI attachment, we expect 3 interfaces total (eth0, eth1, eth2)
        if [ $interface_count -ge 3 ]; then
            log "All expected interfaces discovered ($interface_count >= 3), proceeding"
            break
        else
            log "Waiting for additional ENIs to be attached by Lambda ($interface_count/3 found)..."
            sleep $check_interval
            wait_time=$((wait_time + check_interval))
        fi
    done
    
    if [ $interface_count -lt 3 ]; then
        log "WARNING: Expected 3 interfaces but only found $interface_count after 300 seconds"
    fi
    
    # Final interface status report
    log "Final network interface configuration:"
    for interface in $current_interfaces; do
        log "Interface $interface: $(ip addr show $interface 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1 || echo 'No IP')"
    done
}

# Wait for Lambda ENI attachment and configure interfaces
discover_and_configure_interfaces

# Enable rc.local for interface persistence
systemctl enable rc-local
chmod +x /etc/rc.d/rc.local

# =======================
# HUGEPAGES MOUNT POINTS
# =======================
log "Creating hugepages mount points"
mkdir -p /mnt/huge-2m /mnt/huge-1g

# Add hugepages mounts to fstab
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

# Add performance optimizations to rc.local
cat << 'PERF_SCRIPT' >> /etc/rc.d/rc.local
# Disable transparent hugepages
echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo never > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true

# Mount hugepages if not already mounted
if ! mountpoint -q /mnt/huge-2m; then
    mount -t hugetlbfs -o pagesize=2M nodev /mnt/huge-2m 2>/dev/null || true
fi
if ! mountpoint -q /mnt/huge-1g; then
    mount -t hugetlbfs -o pagesize=1G nodev /mnt/huge-1g 2>/dev/null || true
fi
PERF_SCRIPT

# Create verification script
cat << 'VERIFY_SCRIPT' > /usr/local/bin/verify-dpdk-setup.sh
#!/bin/bash
echo "=== DPDK High-Performance Node Verification ==="
echo "Date: $(date)"
echo

echo "=== Hugepages Status ==="
grep -i huge /proc/meminfo
echo

echo "=== Kernel Command Line ==="
cat /proc/cmdline | tr ' ' '\n' | grep -E '(hugepages|default_hugepagesz)'
echo

echo "=== Network Interfaces ==="
ip link show | grep -E '^[0-9]+:' | awk '{print $2}' | tr -d ':'
echo

echo "=== PCI Devices ==="
lspci -d 1d0f: || echo "No ENA devices found"
echo

echo "=== DPDK Device Binding Status ==="
/opt/dpdk/dpdk-devbind.py --status
echo

echo "=== SR-IOV Configuration ==="
[ -f /etc/pcidp/config.json ] && cat /etc/pcidp/config.json || echo "No SR-IOV config found"
echo

echo "=== CPU Information ==="
lscpu | grep -E "(CPU\(s\)|NUMA node|Model name)"
echo "=== End Verification ==="
VERIFY_SCRIPT

chmod +x /usr/local/bin/verify-dpdk-setup.sh

# Start initial services
systemctl start sriov-init.service

# If hugepages need to be configured, schedule reboot
if [ "$HUGEPAGES_CONFIGURED" = "false" ]; then
    touch /var/lib/hugepages-configured
    log "Hugepages configured, scheduling reboot"
    
    # Create post-reboot verification
    cat << 'POST_REBOOT_SCRIPT' > /usr/local/bin/post-reboot-verification.sh
#!/bin/bash
sleep 30
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Post-reboot DPDK verification starting" >> /var/log/high-perf-setup.log
/usr/local/bin/verify-dpdk-setup.sh >> /var/log/high-perf-setup.log
systemctl start config-sriov.service
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Post-reboot DPDK verification completed" >> /var/log/high-perf-setup.log
POST_REBOOT_SCRIPT
    
    chmod +x /usr/local/bin/post-reboot-verification.sh
    echo "/usr/local/bin/post-reboot-verification.sh" >> /etc/rc.d/rc.local
    
    # Schedule reboot
    cat << 'REBOOT_SCRIPT' > /usr/local/bin/delayed-reboot.sh
#!/bin/bash
sleep 60
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Rebooting for DPDK hugepages configuration" >> /var/log/high-perf-setup.log
reboot
REBOOT_SCRIPT
    
    chmod +x /usr/local/bin/delayed-reboot.sh
    nohup /usr/local/bin/delayed-reboot.sh &
else
    log "Hugepages already configured, starting services"
    /usr/local/bin/verify-dpdk-setup.sh >> /var/log/high-perf-setup.log
    systemctl start config-sriov.service
fi

log "DPDK-enabled high-performance userdata setup completed"

--==BOUNDARY==--