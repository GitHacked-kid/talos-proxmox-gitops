#!/usr/bin/env bash

################################################################################
# Homelab Master Deployment Script
# 
# This is the master script that orchestrates all layers:
# - Layer 0: Manual (PiKVM + Proxmox setup)
# - Layer 1: Infrastructure (VMs + LXC containers)
# - Layer 2: Configuration (Ansible)
# - Layer 3: Talos K8s Setup
# - Layer 4: GitOps (ArgoCD)
#
# Usage: ./deploy-homelab.sh [--skip-layer1] [--skip-layer2] [--skip-layer3] [--skip-layer4]
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}"

# Layer control flags
SKIP_LAYER1=false
SKIP_LAYER2=false
SKIP_LAYER3=false
SKIP_LAYER4=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-layer1)
            SKIP_LAYER1=true
            shift
            ;;
        --skip-layer2)
            SKIP_LAYER2=true
            shift
            ;;
        --skip-layer3)
            SKIP_LAYER3=true
            shift
            ;;
        --skip-layer4)
            SKIP_LAYER4=true
            shift
            ;;
        --help)
            cat << EOF
Homelab Master Deployment Script

Usage: $0 [OPTIONS]

Options:
  --skip-layer1    Skip Layer 1 (Infrastructure deployment)
  --skip-layer2    Skip Layer 2 (Ansible configuration)
  --skip-layer3    Skip Layer 3 (Talos K8s setup)
  --skip-layer4    Skip Layer 4 (GitOps deployment)
  --help           Show this help message

Layers:
  Layer 0: Manual setup (PiKVM + Proxmox)
  Layer 1: Infrastructure (Terraform - VMs + LXC)
  Layer 2: Configuration (Ansible)
  Layer 3: Talos Kubernetes Setup
  Layer 4: GitOps (ArgoCD)

EOF
            exit 0
            ;;
    esac
done

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

log_layer() {
    echo -e "${MAGENTA}[$(date +'%Y-%m-%d %H:%M:%S')] LAYER:${NC} $*"
}

print_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║                  HOMELAB MASTER DEPLOYMENT                   ║
║                                                               ║
║  "Get coffee and watch the magic happen! ☕"                 ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

Architecture:
  ┌─────────────────────────────────────────────────────────┐
  │ Layer 0: Physical Setup (Manual)                       │
  │   • PiKVM for remote management                         │
  │   • Proxmox VE server running                           │
  └─────────────────────────────────────────────────────────┘
  ┌─────────────────────────────────────────────────────────┐
  │ Layer 1: Infrastructure (Terraform)                     │
  │   • 3 Talos K8s VMs (1 CP + 2 Workers)                 │
  │   • 2 Ubuntu VMs (VPN + NFS)                           │
  │   • 4 LXC Containers (Apps)                            │
  └─────────────────────────────────────────────────────────┘
  ┌─────────────────────────────────────────────────────────┐
  │ Layer 2: Configuration (Ansible)                        │
  │   • Configure VPN (OpenVPN)                            │
  │   • Configure NFS Server                               │
  │   • Setup LXC applications                             │
  └─────────────────────────────────────────────────────────┘
  ┌─────────────────────────────────────────────────────────┐
  │ Layer 3: Kubernetes (Talos)                             │
  │   • Generate cluster config                            │
  │   • Bootstrap Kubernetes                               │
  └─────────────────────────────────────────────────────────┘
  ┌─────────────────────────────────────────────────────────┐
  │ Layer 4: GitOps (ArgoCD)                                │
  │   • Deploy ArgoCD                                       │
  │   • Apply app-of-apps pattern                          │
  └─────────────────────────────────────────────────────────┘

EOF
}

wait_for_user() {
    local message="$1"
    echo ""
    log_warning "$message"
    read -p "Press ENTER to continue, or CTRL+C to abort..."
    echo ""
}

layer0_check() {
    log_layer "=== LAYER 0: Physical Setup Check ==="
    
    log "Verifying Layer 0 prerequisites..."
    
    echo ""
    log_info "Please confirm the following:"
    log_info "  ✓ PiKVM is connected and accessible"
    log_info "  ✓ Proxmox VE is running and accessible"
    log_info "  ✓ Proxmox API token is created"
    log_info "  ✓ SSH access to Proxmox is configured"
    echo ""
    
    wait_for_user "Have you completed all Layer 0 prerequisites?"
    
    log "✓ Layer 0 check complete"
}

layer1_prepare() {
    log_layer "=== LAYER 1A: Proxmox Preparation ==="
    
    cd "${ROOT_DIR}/terraform/proxmox-homelab"
    
    log "Running Layer 1 preparation script..."
    log_info "This will SSH to Proxmox and prepare templates/ISOs"
    
    if [[ -x "./layer1-prepare.sh" ]]; then
        ./layer1-prepare.sh
    else
        log_error "layer1-prepare.sh not found or not executable"
        exit 1
    fi
    
    log "✓ Layer 1 preparation complete"
}

layer1_deploy() {
    if [[ "$SKIP_LAYER1" == true ]]; then
        log_warning "Skipping Layer 1 deployment (--skip-layer1 flag)"
        return 0
    fi
    
    log_layer "=== LAYER 1B: Infrastructure Deployment ==="
    
    cd "${ROOT_DIR}/terraform/proxmox-homelab"
    
    log "Running Layer 1 deployment script..."
    
    if [[ -x "./layer1-deploy.sh" ]]; then
        ./layer1-deploy.sh
    else
        log_error "layer1-deploy.sh not found or not executable"
        exit 1
    fi
    
    log "✓ Layer 1 deployment complete"
    
    # Wait for VMs to be fully ready
    log_info "Waiting 60 seconds for VMs and containers to fully boot..."
    sleep 60
}

layer2_configure() {
    if [[ "$SKIP_LAYER2" == true ]]; then
        log_warning "Skipping Layer 2 configuration (--skip-layer2 flag)"
        return 0
    fi
    
    log_layer "=== LAYER 2: Application Configuration ==="
    
    cd "${ROOT_DIR}/ansible"
    
    log "Running Ansible playbooks..."
    log_warning "Note: Layer 2 playbooks need to be created!"
    log_info "Skipping for now - manual configuration required"
    
    # TODO: Uncomment when ansible playbooks are ready
    # if [[ -f "site.yaml" ]]; then
    #     ansible-playbook -i inventory.yml site.yaml
    # else
    #     log_warning "Ansible site.yaml not found, skipping Layer 2"
    # fi
    
    log "✓ Layer 2 configuration complete (or skipped)"
}

layer3_talos() {
    if [[ "$SKIP_LAYER3" == true ]]; then
        log_warning "Skipping Layer 3 (--skip-layer3 flag)"
        return 0
    fi
    
    log_layer "=== LAYER 3: Talos Kubernetes Setup ==="
    
    cd "${ROOT_DIR}/talos"
    
    log "Setting up Talos Kubernetes cluster..."
    log_warning "Note: Talos setup script needs to be configured with IPs!"
    log_info "Skipping for now - manual configuration required"
    
    # TODO: Uncomment when talos script is updated with static IPs
    # if [[ -x "./setup-talos-cluster.sh" ]]; then
    #     ./setup-talos-cluster.sh
    # else
    #     log_warning "Talos setup script not found, skipping Layer 3"
    # fi
    
    log "✓ Layer 3 setup complete (or skipped)"
}

layer4_gitops() {
    if [[ "$SKIP_LAYER4" == true ]]; then
        log_warning "Skipping Layer 4 (--skip-layer4 flag)"
        return 0
    fi
    
    log_layer "=== LAYER 4: GitOps Deployment ==="
    
    cd "${ROOT_DIR}/gitops"
    
    log "Deploying ArgoCD and GitOps..."
    log_warning "Note: GitOps script needs to be configured!"
    log_info "Skipping for now - manual configuration required"
    
    # TODO: Uncomment when gitops is ready
    # if [[ -x "./argocd_install.sh" ]]; then
    #     ./argocd_install.sh
    # else
    #     log_warning "ArgoCD install script not found, skipping Layer 4"
    # fi
    
    log "✓ Layer 4 deployment complete (or skipped)"
}

show_summary() {
    cat << 'EOF'

╔═══════════════════════════════════════════════════════════════╗
║                    DEPLOYMENT COMPLETE! 🎉                    ║
╚═══════════════════════════════════════════════════════════════╝

Your Homelab Status:

✅ Layer 0: Physical Setup
✅ Layer 1: Infrastructure (9 resources deployed)
⚠️  Layer 2: Configuration (Manual steps required)
⚠️  Layer 3: Talos K8s (Manual steps required)
⚠️  Layer 4: GitOps (Manual steps required)

Access Information:

  Proxmox:     https://10.20.0.10:8006
  
  Talos CP:    10.20.0.40
  Talos W1:    10.20.0.41
  Talos W2:    10.20.0.42
  
  VPN VM:      10.20.0.43
  NFS VM:      10.20.0.44
  
  Jellyfin:    10.20.0.45
  Pi-hole:     10.20.0.46
  Redis:       10.20.0.47
  PostgreSQL:  10.20.0.48

Next Manual Steps:

1. Configure VPN on ubuntu-vpn (10.20.0.43)
   ssh ubuntu@10.20.0.43
   curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh
   bash openvpn-install.sh

2. Configure NFS on ubuntu-nfs (10.20.0.44)
   ssh ubuntu@10.20.0.44
   # Setup NFS exports

3. Setup Talos Kubernetes cluster
   cd talos
   # Update setup script with static IPs
   # Run: ./setup-talos-cluster.sh

4. Deploy ArgoCD and applications
   cd gitops
   ./argocd_install.sh
   kubectl apply -f app-of-apps.yaml

Enjoy your automated homelab! ☕

EOF
}

# Main execution
main() {
    print_banner
    log "Starting homelab deployment..."
    log "Deployment completed successfully!"
    echo ""
    
    local start_time=$SECONDS
    
    # Execute layers
    layer0_check
    layer1_prepare
    layer1_deploy
    layer2_configure
    layer3_talos
    layer4_gitops
    
    local end_time=$SECONDS
    local duration=$((end_time - start_time))
    
    show_summary
    
    log "✓ Homelab deployment completed!"
    log "Total time: ${duration} seconds ($(($duration / 60)) minutes)"
    log "Check terminal output above for any issues"
}

# Run main function
main "$@"
