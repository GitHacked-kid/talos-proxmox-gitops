#!/usr/bin/env bash

################################################################################
# Homelab Layer 1 - Preparation Script
# 
# This script prepares your Proxmox server with:
# 1. Talos Linux ISO (for Kubernetes nodes)
# 2. Ubuntu 24.04 LXC template (for containers)
# Note: Ubuntu VM template (ubuntu-temp) should already exist manually
#
# This script SSHs into your Proxmox node and runs the setup
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - UPDATE THESE VALUES
PROXMOX_HOST="${PROXMOX_HOST:-10.20.0.10}"
PROXMOX_USER="${PROXMOX_USER:-root}"
PROXMOX_NODE="${PROXMOX_NODE:-alif}"
PROXMOX_SSH_PORT="${PROXMOX_SSH_PORT:-22}"

# Template configuration
UBUNTU_TEMPLATE_ID=9001
UBUNTU_TEMPLATE_NAME="ubuntu-2404-cloudinit-template"
STORAGE="local-lvm"
TALOS_VERSION="v1.11.5"

# Functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"
}

print_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║        HOMELAB LAYER 1 - PROXMOX PREPARATION                 ║
║                                                               ║
║  Preparing:                                                   ║
║  • Talos Linux ISO                                           ║
║  • Ubuntu 24.04 LXC Template for containers                  ║
║  NOTE: ubuntu-temp VM template should exist manually         ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
}

check_ssh_access() {
    log "Checking SSH access to Proxmox..."
    
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" exit 2>/dev/null; then
        log_error "Cannot SSH to Proxmox server!"
        log_error "Please ensure:"
        log_error "  1. SSH key is added: ssh-copy-id ${PROXMOX_USER}@${PROXMOX_HOST}"
        log_error "  2. Proxmox host is reachable: ${PROXMOX_HOST}"
        log_error "  3. SSH port is correct: ${PROXMOX_SSH_PORT}"
        exit 1
    fi
    
    log "✓ SSH access verified"
}

upload_talos_iso() {
    log "Checking Talos ISO..."
    
    # Check if ISO already exists
    ISO_EXISTS=$(ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
        "ls /var/lib/vz/template/iso/metal-amd64.iso 2>/dev/null || echo 'notfound'")
    
    if [[ "$ISO_EXISTS" != "notfound" ]]; then
        log_info "Talos ISO already exists, skipping download"
        return 0
    fi
    
    log "Downloading Talos ${TALOS_VERSION} ISO to Proxmox..."
    
    ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" bash << EOF
set -e
cd /var/lib/vz/template/iso/
wget -q --show-progress https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/metal-amd64.iso || \
wget https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/metal-amd64.iso
EOF
    
    log "✓ Talos ISO uploaded successfully"
}

download_lxc_template() {
    log "Checking Debian 13 LXC template..."
    
    # Check if LXC template already exists
    LXC_TEMPLATE_EXISTS=$(ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
        "ls /var/lib/vz/template/cache/debian-13-standard_13.1-2_amd64.tar.zst 2>/dev/null || echo 'notfound'")
    
    if [[ "$LXC_TEMPLATE_EXISTS" != "notfound" ]]; then
        log_info "Debian LXC template already exists, skipping download"
        return 0
    fi
    
    log "Downloading Debian 13 LXC template..."
    
    ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" bash << 'EOF'
set -e
pveam update
pveam download local debian-13-standard_13.1-2_amd64.tar.zst
EOF
    
    log "✓ Debian LXC template downloaded successfully"
}

check_ubuntu_template() {
    log "Checking ubuntu-temp VM template..."
    
    # Check if ubuntu-temp template exists
    TEMPLATE_EXISTS=$(ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
        "qm list | grep ubuntu-temp || echo 'notfound'")
    
    if [[ "$TEMPLATE_EXISTS" == "notfound" ]]; then
        log_error "ubuntu-temp VM template not found!"
        log_error "Please create the ubuntu-temp template manually before running this script"
        log_error "This template should be an Ubuntu VM with cloud-init support"
        exit 1
    fi
    
    log "✓ ubuntu-temp VM template exists"

}

verify_setup() {
    log "Verifying setup..."
    
    # Verify Talos ISO
    log_info "Checking Talos ISO..."
    ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
        "ls -lh /var/lib/vz/template/iso/metal-amd64.iso"
    
    # Verify ubuntu-temp VM template
    log_info "Checking ubuntu-temp VM template..."
    ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
        "qm list | grep ubuntu-temp"
    
    # Verify LXC template
    log_info "Checking Debian LXC template..."
    ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
        "ls -lh /var/lib/vz/template/cache/debian-13-standard_13.1-2_amd64.tar.zst"
    
    log "✓ Verification complete"
}

show_next_steps() {
    cat << EOF

╔═══════════════════════════════════════════════════════════════╗
║                  PREPARATION COMPLETED!                       ║
╚═══════════════════════════════════════════════════════════════╝

Resources verified:
  ✓ Talos ISO: /var/lib/vz/template/iso/metal-amd64.iso
  ✓ Ubuntu VM Template: ubuntu-temp (manually created)
  ✓ Ubuntu LXC Template: ubuntu-24.04-standard_24.04-2_amd64.tar.zst

Next Steps:
  1. Review terraform.auto.tfvars for Proxmox credentials
  2. Run: ./layer1-deploy.sh

EOF
}

# Main execution
main() {
    print_banner
    
    log "Starting Layer 1 preparation..."
    log_info "Proxmox Host: ${PROXMOX_HOST}"
    log_info "Proxmox Node: ${PROXMOX_NODE}"
    echo ""
    
    check_ssh_access
    upload_talos_iso
    download_lxc_template
    check_ubuntu_template
    verify_setup
    show_next_steps
    
    log "✓ Layer 1 preparation completed successfully!"
}

# Run main function
main "$@"
