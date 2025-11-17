#!/usr/bin/env bash

################################################################################
# Terraform Destroy Script - Homelab Infrastructure
# 
# Simple script to destroy Terraform-managed infrastructure
# WARNING: This will destroy all VMs and LXC containers!
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform/proxmox-homelab"

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

print_banner() {
    echo -e "${RED}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                    ⚠️  DESTROY INFRASTRUCTURE  ⚠️             ║
║                                                               ║
║   This will destroy all Terraform-managed resources:         ║
║   - All VMs (Talos nodes, Ubuntu VMs)                        ║
║   - All LXC containers                                        ║
║                                                               ║
║                    THIS CANNOT BE UNDONE!                    ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

confirm_destruction() {
    echo ""
    log_warning "Are you sure you want to destroy the infrastructure?"
    read -p "Type 'yes' to confirm: " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled."
        exit 0
    fi
}

terraform_destroy() {
    log "Destroying Terraform infrastructure..."
    
    if [ ! -d "${TERRAFORM_DIR}" ]; then
        log_error "Terraform directory not found: ${TERRAFORM_DIR}"
        exit 1
    fi
    
    cd "${TERRAFORM_DIR}"
    
    # Check if Terraform state exists
    if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
        log "No Terraform state found, nothing to destroy"
        return 0
    fi
    
    # Initialize Terraform
    log "Initializing Terraform..."
    if ! terraform init; then
        log_error "Terraform initialization failed"
        exit 1
    fi
    
    # Destroy infrastructure
    log "Destroying infrastructure..."
    if terraform destroy -auto-approve; then
        log "✓ Infrastructure destroyed successfully"
    else
        log_error "Infrastructure destruction failed"
        exit 1
    fi
}

# Main execution
main() {
    print_banner
    confirm_destruction
    terraform_destroy
    log "✅ Terraform destroy completed!"
}

# Execute main function
main "$@"