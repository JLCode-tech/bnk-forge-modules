Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="
MIME-Version: 1.0

--==MYBOUNDARY==
Content-Type: text/cloud-boothook; charset="us-ascii"
#!/bin/bash
set -euo pipefail
mkdir -p /var/lib/dpdk-setup/
echo "PHASE_1_STARTED" > /var/lib/dpdk-setup/phase1.state

--==MYBOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"
#!/bin/bash
set -euo pipefail

# Config from Terraform
S3_BUCKET="${s3_bucket_name}"
REGION="${region}"
HUGEPAGES_2MI="${hugepages_2mi}"
HUGEPAGES_1GI="${hugepages_1gi}"
F5_BNK_ENABLED="${f5_bnk_enabled}"
F5_TMM_CPU_CORES="${f5_tmm_cpu_cores}"
F5_NUMA_NODE="${f5_numa_node}"
TMM_DATA_PLANE_MODE="${tmm_data_plane_mode}"

STATE_DIR="/var/lib/dpdk-setup"
LOG_FILE="/var/log/dpdk-setup.log"
CHECKPOINT_FILE="$STATE_DIR/checkpoints"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
error_exit() { log "ERROR: $1"; echo "FAILED: $1" > "$STATE_DIR/error.state"; exit 1; }
checkpoint() { log "CHECKPOINT: $1"; echo "$1:$(date +%s)" >> "$CHECKPOINT_FILE"; }
is_checkpoint_complete() { grep -q "^$1:" "$CHECKPOINT_FILE" 2>/dev/null; }
retry_with_backoff() {
    local a=1 d=1
    while [ $a -le 5 ]; do
        "$@" && return 0
        [ $a -eq 5 ] && error_exit "Failed after 5 attempts: $*"
        sleep $d; d=$((d*2)); a=$((a+1))
    done
}

get_metadata() {
    local t=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    curl -s -H "X-aws-ec2-metadata-token: $t" "http://169.254.169.254/latest/$1"
}
INSTANCE_ID=$(get_metadata "meta-data/instance-id")
log "DPDK setup - Instance: $INSTANCE_ID"

# PHASE 1: KERNEL PARAMETERS (3-layer: grub drop-in + sysfs + systemd)
if ! is_checkpoint_complete "kernel_params"; then
    log "Phase 1: Kernel parameters"
    KP="default_hugepagesz=2M hugepagesz=2M hugepages=$HUGEPAGES_2MI hugepagesz=1G hugepages=$HUGEPAGES_1GI intel_iommu=on iommu=pt"
    if [ "$F5_BNK_ENABLED" = "true" ]; then
        TC=$(nproc)
        [ $TC -gt $F5_TMM_CPU_CORES ] && KP="$KP isolcpus=$F5_TMM_CPU_CORES-$((TC-1)) nohz_full=$F5_TMM_CPU_CORES-$((TC-1)) rcu_nocbs=$F5_TMM_CPU_CORES-$((TC-1)) numa_balancing=disable"
    fi
    if grep -q "hugepagesz=2M" /proc/cmdline; then
        NEEDS_REBOOT=false
    elif [ "$TMM_DATA_PLANE_MODE" = "sriov" ]; then
        NEEDS_REBOOT=true
        mkdir -p /etc/default/grub.d
        echo "GRUB_CMDLINE_LINUX=\"$${GRUB_CMDLINE_LINUX:-} $KP\"" > /etc/default/grub.d/99-dpdk-hugepages.cfg
        cp /etc/default/grub /etc/default/grub.backup
        grep -q "hugepagesz=2M" /etc/default/grub || sed -i "s/biosdevname=0/& $KP/g" /etc/default/grub
        grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        # Kernel mode: skip grub mutation. The 60s-delayed reboot below races with the EKS
        # bootstrap script and interrupts kubelet's first registration. Hugepages are
        # allocated at runtime via sysfs (below) and persisted across future operator-triggered
        # reboots by the systemd-enabled dpdk-hugepages.service. isolcpus/nohz_full/rcu_nocbs
        # would require a reboot to take effect but they are TMM jitter optimizations only —
        # TMM still works via cpuset pinning in the pod spec.
        NEEDS_REBOOT=false
        log "kernel mode: skipping grub mutation, no reboot will be scheduled"
    fi
    echo $HUGEPAGES_2MI > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null || true
    echo $HUGEPAGES_1GI > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages 2>/dev/null || true
    mkdir -p /mnt/huge-2m /mnt/huge-1g
    mount -t hugetlbfs -o pagesize=2M nodev /mnt/huge-2m 2>/dev/null || true
    mount -t hugetlbfs -o pagesize=1G nodev /mnt/huge-1g 2>/dev/null || true
    echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
    echo never > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
    cat << 'HP_SVC' > /usr/lib/systemd/system/dpdk-hugepages.service
[Unit]
Description=DPDK Hugepages
DefaultDependencies=no
Before=kubelet.service
After=local-fs.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/dpdk-hugepages.sh
[Install]
WantedBy=multi-user.target
HP_SVC
    cat << HP_SCRIPT > /usr/local/bin/dpdk-hugepages.sh
#!/bin/bash
echo $HUGEPAGES_2MI > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
echo $HUGEPAGES_1GI > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages
mkdir -p /mnt/huge-2m /mnt/huge-1g
mount -t hugetlbfs -o pagesize=2M nodev /mnt/huge-2m 2>/dev/null || true
mount -t hugetlbfs -o pagesize=1G nodev /mnt/huge-1g 2>/dev/null || true
echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
HP_SCRIPT
    chmod +x /usr/local/bin/dpdk-hugepages.sh
    systemctl enable dpdk-hugepages.service
    checkpoint "kernel_params"
fi

# PHASE 2: SYSTEM PACKAGES
if ! is_checkpoint_complete "packages"; then
    log "Phase 2: Packages"
    retry_with_backoff yum update -y
    retry_with_backoff yum install -y net-tools pciutils wget curl awscli kernel kernel-devel kernel-headers git gcc make python3 python3-pip numactl-devel libhugetlbfs-utils libpcap-devel
    checkpoint "packages"
fi

# PHASE 3: NETWORK OPTIMIZATIONS
if ! is_checkpoint_complete "network_opts"; then
    log "Phase 3: Network optimizations"
    cat << 'EOF' >> /etc/sysctl.conf
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
EOF
    sysctl -p
    checkpoint "network_opts"
fi

# PHASE 4: DPDK CONTINUATION SERVICE (sriov mode only)
# In kernel mode the data-plane ENIs stay on the ena driver — host-device CNI
# moves the kernel netdev into the TMM pod at scheduling time. No vfio-pci
# binding is needed at boot, so this phase is skipped entirely.
if [ "$TMM_DATA_PLANE_MODE" = "sriov" ] && ! is_checkpoint_complete "dpdk_service"; then
    log "Phase 4: DPDK continuation service (sriov mode)"
    retry_with_backoff aws s3 cp "s3://$S3_BUCKET/dpdk-setup.sh" /usr/local/bin/dpdk-setup.sh --region "$REGION"
    chmod +x /usr/local/bin/dpdk-setup.sh
    cat << 'DSVC' > /usr/lib/systemd/system/dpdk-continuation.service
[Unit]
Description=DPDK Setup Continuation
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/dpdk-continuation.sh
RemainAfterExit=yes
TimeoutStartSec=1200
Restart=on-failure
RestartSec=30
[Install]
WantedBy=multi-user.target
DSVC
    cat << 'CSCRIPT' > /usr/local/bin/dpdk-continuation.sh
#!/bin/bash
set -euo pipefail
shopt -s extglob
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/dpdk-continuation.log; }
log "Starting DPDK continuation"
MW=600; WT=0; TGT=3
while [ $WT -lt $MW ]; do
    shopt -s nullglob; ei=(/sys/class/net/eth+([0-9])); IC=$(ls /sys/class/net/ | grep -E '^eth[0-9]+$' | wc -l); shopt -u nullglob
    [ $IC -ge $TGT ] && break
    [ $WT -gt 300 ] && [ $IC -lt 2 ] && break
    sleep 15; WT=$((WT+15))
done
/usr/local/bin/dpdk-setup.sh "$HUGEPAGES_2MI" "$HUGEPAGES_1GI" "$REGION" "$S3_BUCKET" "$F5_BNK_ENABLED" "$F5_TMM_CPU_CORES" "$F5_NUMA_NODE"
systemctl restart kubelet
log "DPDK continuation completed"
CSCRIPT
    chmod +x /usr/local/bin/dpdk-continuation.sh
    systemctl enable dpdk-continuation.service
    checkpoint "dpdk_service"
elif [ "$TMM_DATA_PLANE_MODE" != "sriov" ]; then
    log "Phase 4: skipped (TMM_DATA_PLANE_MODE=$TMM_DATA_PLANE_MODE — kernel mode keeps ENIs on ena driver)"
fi

# PHASE 5: NODE CONFIGURATION
if ! is_checkpoint_complete "node_config"; then
    mkdir -p /etc/node-config
    cat << NC > /etc/node-config/high-perf-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: node-config
data:
  hugepages_2mi: "$HUGEPAGES_2MI"
  hugepages_1gi: "$HUGEPAGES_1GI"
  f5_bnk_enabled: "$F5_BNK_ENABLED"
  s3_bucket: "$S3_BUCKET"
  region: "$REGION"
  tmm_data_plane_mode: "$TMM_DATA_PLANE_MODE"
  dpdk_enabled: "$([ "$TMM_DATA_PLANE_MODE" = "sriov" ] && echo true || echo false)"
  sriov_enabled: "$([ "$TMM_DATA_PLANE_MODE" = "sriov" ] && echo true || echo false)"
NC
    checkpoint "node_config"
fi

# PHASE 6: REBOOT OR CONTINUE
# Reboot is still required in both modes — hugepages + isolcpus are kernel
# params set via grub. The dpdk-continuation service is only triggered when
# in sriov mode (it does the vfio-pci binding).
if [ "$NEEDS_REBOOT" = "true" ]; then
    if ! is_checkpoint_complete "reboot_scheduled"; then
        log "Scheduling reboot for kernel params"
        if [ "$TMM_DATA_PLANE_MODE" = "sriov" ]; then
            cat << 'PRV' > /usr/local/bin/post-reboot-validation.sh
#!/bin/bash
echo "[$(date)] Post-reboot: starting DPDK continuation (sriov mode)" >> /var/log/post-reboot.log
systemctl start dpdk-continuation.service
PRV
            chmod +x /usr/local/bin/post-reboot-validation.sh
            echo "/usr/local/bin/post-reboot-validation.sh" >> /etc/rc.d/rc.local
            chmod +x /etc/rc.d/rc.local
            systemctl enable rc-local
        else
            log "kernel mode: no post-reboot DPDK continuation needed"
        fi
        checkpoint "reboot_scheduled"
        nohup bash -c 'sleep 60; reboot' &
    fi
else
    if [ "$TMM_DATA_PLANE_MODE" = "sriov" ]; then
        log "No reboot needed, starting DPDK continuation"
        systemctl start dpdk-continuation.service &
    else
        log "No reboot needed and kernel mode active — DPDK continuation skipped"
    fi
fi
log "Userdata setup completed (mode=$TMM_DATA_PLANE_MODE)"

--==MYBOUNDARY==--
