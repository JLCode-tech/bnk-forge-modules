#!/bin/bash
# Install SR-IOV CNI configuration
# Sentinel: CNI binary installation is deferred to the Kubernetes DaemonSet to avoid
# insecure downloads and ensure version pinning. This script now only handles
# node-specific configuration.

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/sriov-cni-install.log
}

ARCH=$(uname -m)

log "Configuring SR-IOV CNI for architecture: $ARCH"

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
else
    log "No specific optimizations needed for $ARCH"
fi

# Sentinel: The previous logic attempted to download binaries from GitHub Releases 'latest',
# which was insecure (no verification) and broken (upstream does not publish binaries).
# Installation is now handled by the 'sriov-cni-installer' DaemonSet.
log "Sentinel: SR-IOV CNI binary installation skipped. Relying on DaemonSet for CNI installation."

if [ "$ARCH" = "aarch64" ]; then
    log "WARNING: Verify that an ARM64-compatible DaemonSet is deployed for SR-IOV CNI."
fi

log "SR-IOV CNI configuration script completed"
