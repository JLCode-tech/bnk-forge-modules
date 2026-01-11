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
# Optimization: Use Bash glob expansion instead of ls | grep to avoid spawning processes
shopt -s nullglob
for iface_path in /sys/class/net/eth*; do
    iface=${iface_path##*/}
    if [ -d "$iface_path" ]; then
        log "Bringing up interface: $iface"
        ip link set $iface up || true
    fi
done
shopt -u nullglob

log "SR-IOV initialization completed"
