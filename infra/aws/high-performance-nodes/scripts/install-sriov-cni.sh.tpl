#!/bin/bash
# Install SR-IOV CNI binary for both x86_64 and ARM64

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/sriov-cni-install.log
}

ARCH=$(uname -m)

log "Installing SR-IOV CNI binary for architecture: $ARCH"

# Create CNI bin directory if it doesn't exist
mkdir -p /opt/cni/bin/

# Determine the correct download URL based on runtime architecture
# Sentinel: Pinned to specific version v2.10.0 to prevent supply chain attacks via mutable tags
SRIOV_CNI_VERSION="v2.10.0"

case $ARCH in
    "x86_64")
        SRIOV_CNI_URL="https://github.com/k8snetworkplumbingwg/sriov-cni/releases/download/${SRIOV_CNI_VERSION}/sriov-cni-amd64.tgz"
        log "Using x86_64/amd64 SR-IOV CNI binary (Version: ${SRIOV_CNI_VERSION})"
        ;;
    "aarch64")
        SRIOV_CNI_URL="https://github.com/k8snetworkplumbingwg/sriov-cni/releases/download/${SRIOV_CNI_VERSION}/sriov-cni-arm64.tgz"
        log "Using ARM64 SR-IOV CNI binary (Version: ${SRIOV_CNI_VERSION})"
        ;;
    *)
        log "ERROR: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Download and install SR-IOV CNI binary
cd /tmp
log "Downloading SR-IOV CNI from: $SRIOV_CNI_URL"

# Download with retry logic
for i in {1..3}; do
    if wget -q --timeout=30 "$SRIOV_CNI_URL" -O sriov-cni.tgz; then
        log "Downloaded SR-IOV CNI successfully on attempt $i"
        break
    else
        log "Download attempt $i failed, retrying..."
        sleep 5
    fi
done

# Verify download
if [ ! -f "sriov-cni.tgz" ]; then
    log "ERROR: Failed to download SR-IOV CNI binary"
    exit 1
fi

# Extract and install
log "Extracting SR-IOV CNI binary"
tar -xzf sriov-cni.tgz

if [ -f "sriov" ]; then
    cp sriov /opt/cni/bin/
    chmod +x /opt/cni/bin/sriov
    log "SR-IOV CNI binary installed successfully"
else
    log "ERROR: SR-IOV binary not found in extracted files"
    exit 1
fi

# Verify installation
if [ -f "/opt/cni/bin/sriov" ] && [ -x "/opt/cni/bin/sriov" ]; then
    log "SR-IOV CNI binary verification successful"
    ls -la /opt/cni/bin/sriov
    
    # Test execution
    if /opt/cni/bin/sriov --help >/dev/null 2>&1; then
        log "SR-IOV CNI binary is executable and functional"
    else
        log "WARNING: SR-IOV CNI binary exists but may not be functional"
    fi
else
    log "ERROR: SR-IOV CNI binary installation verification failed"
    exit 1
fi

# Cleanup
rm -f /tmp/sriov-cni.tgz /tmp/sriov

log "SR-IOV CNI installation completed successfully for $ARCH"

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

log "SR-IOV CNI installation script completed"