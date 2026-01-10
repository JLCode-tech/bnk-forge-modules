#!/bin/bash
# Install SR-IOV CNI binary for both x86_64 and ARM64
# SECURITY UPDATE: Removed insecure download of binaries.
# This script now relies on the DaemonSet to install CNI plugins.

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/sriov-cni-install.log
}

ARCH=$(uname -m)

log "SR-IOV CNI installation wrapper started for architecture: $ARCH"
log "Sentinel: Host-level SR-IOV CNI binary download has been removed to prevent supply chain attacks."
log "Sentinel: Please rely on the approved DaemonSet with pinned container images for CNI installation."

# Architecture-specific optimizations for ARM64/Graviton
if [ "$ARCH" = "aarch64" ]; then
    log "Applying ARM64/Graviton-specific optimizations"
    
    # Create Graviton-specific configuration
    cat << 'GRAVITON_CONFIG' > /etc/sriov-cni-graviton.conf
# Graviton-specific SR-IOV CNI optimizations
export SRIOV_CNI_ARM64_OPTIMIZED=true
export SRIOV_CNI_GRAVITON_MODE=true

# ARM64 DPDK optimizations
export DPDK_ARM64_NATIVE=true
export DPDK_GRAVITON_TARGET=true
GRAVITON_CONFIG
    
    log "Graviton-specific optimizations applied"
fi

log "SR-IOV CNI installation wrapper completed"
