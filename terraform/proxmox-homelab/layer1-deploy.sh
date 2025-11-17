#!/usr/bin/env bash

################################################################################
# Homelab Layer 1 Deployment Script
# 
# This script deploys:
# - 3 node Talos Kubernetes cluster (1 control-plane, 2 workers)
# - 2 Ubuntu VMs (VPN and NFS servers)
# - 4 LXC containers (Jellyfin, Pihole, Redis, Postgres)
#
# Prerequisites:
# 1. layer1-prepare.sh has been run successfully
# 2. Proxmox API credentials set in terraform.auto.tfvars
# 3. Templates and ISOs are ready on Proxmox
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}"

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
║          HOMELAB LAYER 1 - INFRASTRUCTURE DEPLOYMENT         ║
║                                                               ║
║  Deploying:                                                   ║
║  • Talos K8s Cluster (1 CP + 2 Workers)                      ║
║  • Ubuntu VPN VM (10.20.0.43)                                ║
║  • Ubuntu NFS VM (10.20.0.44)                                ║
║  • 4 LXC Containers (Jellyfin, Pihole, Redis, Postgres)     ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    log_info "Terraform version: $(terraform version -json | grep -o '"terraform_version":"[^"]*' | cut -d'"' -f4)"
    
    # Check if terraform.auto.tfvars exists
    if [[ ! -f "${TERRAFORM_DIR}/terraform.auto.tfvars" ]]; then
        log_error "terraform.auto.tfvars not found!"
        exit 1
    fi
    
    # Validate API credentials are set
    if ! grep -q "proxmox_api_url" "${TERRAFORM_DIR}/terraform.auto.tfvars"; then
        log_error "Proxmox API URL not configured in terraform.auto.tfvars"
        exit 1
    fi
    
    log "✓ Prerequisites check passed"
}

terraform_init() {
    log "Initializing Terraform..."
    cd "${TERRAFORM_DIR}"
    # check if .terraform directory exists
    if [[ -d .terraform ]]; then
        log_warning ".terraform directory already exists, skipping initialization"
        return 0
    fi
    if terraform init ; then
        log "✓ Terraform initialized successfully"
    else
        log_error "Terraform initialization failed"
        exit 1
    fi
}

terraform_validate() {
    log "Validating Terraform configuration..."
    cd "${TERRAFORM_DIR}"
    
    if terraform validate; then
        log "✓ Terraform configuration is valid"
    else
        log_error "Terraform validation failed"
        exit 1
    fi
}

terraform_validate() {
    log "Validating Terraform configuration..."
    cd "${TERRAFORM_DIR}"
    
    if terraform validate ; then
        log "✓ Terraform configuration is valid"
    else
        log_error "Terraform validation failed"
        exit 1
    fi
}

parse_terraform_plan() {
    log "Parsing Terraform plan for deployment preview..."
    cd "${TERRAFORM_DIR}"
    
    # Get terraform plan output
    local plan_output
    plan_output=$(terraform plan -no-color 2>&1)
    
    log_warning "Terraform Deployment Plan:"
    echo ""
    
    # Parse VMs to be created
    if echo "$plan_output" | grep -q "proxmox_vm_qemu.*will be created"; then
        log_warning "  Virtual Machines:"
        echo "$plan_output" | grep -A 5 "proxmox_vm_qemu" | grep -E "(will be created|name|memory|cores)" | while read -r line; do
            if [[ "$line" == *"will be created"* ]]; then
                vm_name=$(echo "$line" | sed 's/.*\[\(.*\)\].*/\1/')
                log_warning "    • $vm_name"
            fi
        done
        echo ""
    fi
    
    # Parse LXC containers to be created  
    if echo "$plan_output" | grep -q "proxmox_lxc.*will be created"; then
        log_warning "  LXC Containers:"
        echo "$plan_output" | grep -A 3 "proxmox_lxc" | grep -E "(will be created|hostname)" | while read -r line; do
            if [[ "$line" == *"will be created"* ]]; then
                container_name=$(echo "$line" | sed 's/.*\[\(.*\)\].*/\1/')
                log_warning "    • $container_name"
            fi
        done
        echo ""
    fi
    
    # Show resource summary
    local add_count=$(echo "$plan_output" | grep -o "to add" | wc -l | tr -d ' ')
    local change_count=$(echo "$plan_output" | grep -o "to change" | wc -l | tr -d ' ')
    local destroy_count=$(echo "$plan_output" | grep -o "to destroy" | wc -l | tr -d ' ')
    
    log_info "Plan Summary: ${add_count} to add, ${change_count} to change, ${destroy_count} to destroy"
    echo ""
}

terraform_apply() {
    log "Applying Terraform configuration..."
    cd "${TERRAFORM_DIR}"
    
    # Show dynamic terraform plan
    parse_terraform_plan
    
    log_info "Auto-approving deployment for full automation..."
    
    if terraform apply -auto-approve ; then
        log "✓ Infrastructure deployed successfully!"
    else
        log_error "Terraform apply failed"
        exit 1
    fi
}

show_outputs() {
    log "Fetching deployment outputs..."
    cd "${TERRAFORM_DIR}"
    
    echo ""
    log_info "=== Deployment Summary ==="
    terraform output -json | jq '.' || terraform output
    echo ""
}

save_outputs() {
    log "Saving outputs for Layer 2 (Ansible)..."
    cd "${TERRAFORM_DIR}"
    
    # Save outputs to a file that Ansible can use
    terraform output -json > "${SCRIPT_DIR}/../../ansible/terraform_outputs.json"
    log "✓ Outputs saved to: ${SCRIPT_DIR}/../../ansible/terraform_outputs.json"
}

create_ansible_inventory() {
    log "Generating Ansible inventory with dynamic IPs..."
    
    # Get actual deployed IPs from Proxmox
    local vpn_ip=$(ssh root@10.20.0.10 "qm guest cmd 106 network-get-interfaces 2>/dev/null | grep -o '10\.20\.0\.[0-9]*' | head -1" 2>/dev/null || echo "TBD")
    local nfs_ip=$(ssh root@10.20.0.10 "qm guest cmd 102 network-get-interfaces 2>/dev/null | grep -o '10\.20\.0\.[0-9]*' | head -1" 2>/dev/null || echo "TBD")
    local media_ip=$(ssh root@10.20.0.10 "qm guest cmd \$(qm list | grep ubuntu-media | awk '{print \$1}') network-get-interfaces 2>/dev/null | grep -o '10\.20\.0\.[0-9]*' | head -1" 2>/dev/null || echo "TBD")
    
    # Get LXC container IPs
    local redis_vmid=$(ssh root@10.20.0.10 "pct list | grep redis | awk '{print \$1}'" 2>/dev/null)
    local postgres_vmid=$(ssh root@10.20.0.10 "pct list | grep postgres | awk '{print \$1}'" 2>/dev/null)
    local pihole_vmid=$(ssh root@10.20.0.10 "pct list | grep pihole | awk '{print \$1}'" 2>/dev/null)
    
    local redis_ip=$(ssh root@10.20.0.10 "pct exec ${redis_vmid} -- ip addr show eth0 2>/dev/null | grep -o '10\.20\.0\.[0-9]*' | head -1" 2>/dev/null || echo "TBD")
    local postgres_ip=$(ssh root@10.20.0.10 "pct exec ${postgres_vmid} -- ip addr show eth0 2>/dev/null | grep -o '10\.20\.0\.[0-9]*' | head -1" 2>/dev/null || echo "TBD")
    local pihole_ip=$(ssh root@10.20.0.10 "pct exec ${pihole_vmid} -- ip addr show eth0 2>/dev/null | grep -o '10\.20\.0\.[0-9]*' | head -1" 2>/dev/null || echo "TBD")
    
    cat > "${SCRIPT_DIR}/../../ansible/inventory.yml" << EOF
---
# Generated Ansible Inventory - Hybrid Architecture
# VPN: ${vpn_ip}, NFS: ${nfs_ip}, Media: ${media_ip}
# Redis: ${redis_ip}, PostgreSQL: ${postgres_ip}, Pi-hole: ${pihole_ip}

all:
  children:
    ubuntu_vms:
      hosts:
        ubuntu-vpn:
          ansible_host: ${vpn_ip}
          ansible_user: ubuntu
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
          services:
            - openvpn
        ubuntu-nfs:
          ansible_host: ${nfs_ip}
          ansible_user: ubuntu
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
          services:
            - nfs-server
        ubuntu-media:
          ansible_host: ${media_ip}
          ansible_user: ubuntu
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
          services:
            - casaos
            - jellyfin
            - qbittorrent
    
    lxc_containers:
      hosts:
        redis:
          ansible_host: ${redis_ip}
          ansible_user: root
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
          services:
            - redis
        postgres:
          ansible_host: ${postgres_ip}
          ansible_user: root
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
          services:
            - postgres
        pihole:
          ansible_host: ${pihole_ip}
          ansible_user: root
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
          services:
            - pihole
  
  vars:
    ansible_python_interpreter: /usr/bin/python3
    # Network configuration
    network_cidr: "10.20.0.0/24"
    network_gateway: "10.20.0.1"
    # NFS exports
    nfs_server_ip: "${nfs_ip}"
    nfs_export_path: "/srv/nfs/shared"
    # Database configurations
    postgres_db: "homelab"
    postgres_user: "homelab"
    redis_port: 6379
    # Media server configuration
    jellyfin_data_path: "/opt/jellyfin"
EOF
    
    log "✓ Ansible inventory generated with dynamic IPs"
    log_info "VMs: VPN=${vpn_ip}, NFS=${nfs_ip}, Media=${media_ip}"
    log_info "LXC: Redis=${redis_ip}, PostgreSQL=${postgres_ip}, Pi-hole=${pihole_ip}"
}

show_next_steps() {
    cat << 'EOF'

╔═══════════════════════════════════════════════════════════════╗
║                    DEPLOYMENT COMPLETED!                      ║
╚═══════════════════════════════════════════════════════════════╝

Infrastructure Summary:

┌─────────────────────────────────────────────────────────────┐
│ TALOS KUBERNETES CLUSTER                                    │
├─────────────────────────────────────────────────────────────┤
│ Control Plane: talos-cp-01 (10.20.0.40)                    │
│ Worker 1:      talos-wk-01 (10.20.0.41)                    │
│ Worker 2:      talos-wk-02 (10.20.0.42)                    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ UBUNTU VMs                                                  │
├─────────────────────────────────────────────────────────────┤
│ VPN Server:    ubuntu-vpn (10.20.0.43)                     │
│ NFS Server:    ubuntu-nfs (10.20.0.44)                     │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ LXC CONTAINERS                                              │
├─────────────────────────────────────────────────────────────┤
│ Jellyfin:      10.20.0.45                                   │
│ Pi-hole:       10.20.0.46                                   │
│ Redis:         10.20.0.47                                   │
│ PostgreSQL:    10.20.0.48                                   │
└─────────────────────────────────────────────────────────────┘

Next Steps:

1. Wait for all VMs and containers to boot (2-3 minutes)

2. Verify connectivity:
   # Test SSH to Ubuntu VMs
   ssh ubuntu@10.20.0.43
   ssh ubuntu@10.20.0.44
   
   # Test SSH to LXC containers
   ssh root@10.20.0.45

3. Proceed to Layer 2 (Ansible Configuration):
   cd ../../ansible
   ansible-playbook -i inventory.yml site.yaml

4. Configure Talos Cluster (Layer 3):
   cd ../talos
   ./setup-talos-cluster.sh

5. Deploy GitOps (Layer 4):
   cd ../gitops
   ./argocd_install.sh

EOF
}

cleanup() {
    if [[ -f "${TERRAFORM_DIR}/tfplan" ]]; then
        rm -f "${TERRAFORM_DIR}/tfplan"
        log "Cleaned up temporary plan file"
    fi
}

# Main execution
main() {
    print_banner
    log "Starting Layer 1 deployment..."
    echo ""
    
    check_prerequisites
    terraform_init
    terraform_validate
    terraform_apply
    show_outputs
    save_outputs
    create_ansible_inventory
    show_next_steps
    
    cleanup
    
    log "✓ Layer 1 deployment completed successfully!"
    log "Total time: $SECONDS seconds"
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
