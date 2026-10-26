#!/bin/bash
# infrastructure-modules/spk-2.1/far-setup/scripts/parse-versions.sh
# Enhanced version parser for SPK 2.1 manifest

set -euo pipefail

# Read inputs from Terraform
eval "$(jq -r '@sh "MANIFEST_FILE=\(.manifest_file)"')"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [parse-versions] $*" >&2
}

# Function to handle errors
error_exit() {
    log "ERROR: $1"
    jq -nc --arg error "$1" '{"error": $error}'
    exit 1
}

log "Parsing component versions from: $MANIFEST_FILE"

# Verify manifest file exists
if [ ! -f "$MANIFEST_FILE" ]; then
    error_exit "Manifest file not found: $MANIFEST_FILE"
fi

log "Extracting component versions..."

cert_manager=""
flo=""
rabbitmq=""
cwc=""
spk_crds_common=""
spk_crds_service_proxy=""
spk_crds_deprecated=""
f5ingress=""
crd_conversion=""
fluentd=""
dssm=""
observer=""
ipam_controller=""
license_proxy=""
tmm_img=""
f5ingress_img=""
spk_cwc_img=""

# We use awk to find 'name:' followed by 'version:' on the next line
# The logic strictly mimics 'grep -A1 "name: ..." | grep "version:"'
while read -r key value; do
    case "$key" in
        "charts/f5-cert-manager") cert_manager="$value" ;;
        "charts/f5-lifecycle-operator") flo="$value" ;;
        "charts/rabbitmq") rabbitmq="$value" ;;
        "charts/cwc") cwc="$value" ;;
        "charts/f5-spk-crds-common") spk_crds_common="$value" ;;
        "charts/f5-spk-crds-service-proxy") spk_crds_service_proxy="$value" ;;
        "charts/f5-spk-crds-deprecated") spk_crds_deprecated="$value" ;;
        "charts/f5ingress") f5ingress="$value" ;;
        "charts/f5-crdconversion") crd_conversion="$value" ;;
        "charts/f5-toda-fluentd") fluentd="$value" ;;
        "charts/f5-dssm") dssm="$value" ;;
        "charts/f5-toda-observer") observer="$value" ;;
        "charts/f5-ipam-controller") ipam_controller="$value" ;;
        "charts/f5-license-proxy") license_proxy="$value" ;;
        "images/tmm-img") tmm_img="$value" ;;
        "images/f5ingress") f5ingress_img="$value" ;;
        "images/spk-cwc") spk_cwc_img="$value" ;;
    esac
done < <(awk '
    /name:/ {
        for (i=1; i<=NF; i++) {
            if ($i == "name:") {
                # Capture the key (the field after "name:")
                key = $(i+1)
                found_key = 1
                next
            }
        }
    }
    found_key && /version:/ {
        for (i=1; i<=NF; i++) {
            if ($i == "version:") {
                # Found version for the previous name
                print key, $(i+1)
                found_key = 0
                key = ""
                next
            }
        }
    }
    # Reset if we dont find version on the immediate next line
    { found_key = 0; key = "" }
' "$MANIFEST_FILE")

# Validate that critical components were found (charts/f5-cert-manager is absent in BNK 2.4+)
log "Validating critical component versions..."
critical_missing=""

[ -z "$flo" ] && critical_missing="$critical_missing flo"

if [ -n "$critical_missing" ]; then
    error_exit "Critical component versions not found: $critical_missing"
fi

log "Version extraction completed successfully"
log "Found versions: cert_manager=$cert_manager, flo=$flo, cwc=$cwc"

# Output JSON for Terraform
jq -nc \
    --arg cert_manager "$cert_manager" \
    --arg flo "$flo" \
    --arg rabbitmq "$rabbitmq" \
    --arg cwc "$cwc" \
    --arg spk_crds_common "$spk_crds_common" \
    --arg spk_crds_service_proxy "$spk_crds_service_proxy" \
    --arg spk_crds_deprecated "$spk_crds_deprecated" \
    --arg f5ingress "$f5ingress" \
    --arg crd_conversion "$crd_conversion" \
    --arg fluentd "$fluentd" \
    --arg dssm "$dssm" \
    --arg observer "$observer" \
    --arg ipam_controller "$ipam_controller" \
    --arg license_proxy "$license_proxy" \
    --arg tmm_img "$tmm_img" \
    --arg f5ingress_img "$f5ingress_img" \
    --arg spk_cwc_img "$spk_cwc_img" \
    '{
        "cert_manager": $cert_manager,
        "flo": $flo,
        "rabbitmq": $rabbitmq,
        "cwc": $cwc,
        "spk_crds_common": $spk_crds_common,
        "spk_crds_service_proxy": $spk_crds_service_proxy,
        "spk_crds_deprecated": $spk_crds_deprecated,
        "f5ingress": $f5ingress,
        "crd_conversion": $crd_conversion,
        "fluentd": $fluentd,
        "dssm": $dssm,
        "observer": $observer,
        "ipam_controller": $ipam_controller,
        "license_proxy": $license_proxy,
        "tmm_img": $tmm_img,
        "f5ingress_img": $f5ingress_img,
        "spk_cwc_img": $spk_cwc_img
    }'

log "Component versions parsed and returned successfully"
