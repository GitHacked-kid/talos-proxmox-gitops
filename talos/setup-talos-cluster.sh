#!/bin/bash
# Talos Linux Kubernetes Cluster Setup - Layer 3
# Based on: https://mirceanton.com/posts/the-best-os-for-kubernetes/

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="homelab-cluster"
CLUSTER_VIP="10.20.0.50"  # Virtual IP for HA control plane

# Talos node hostnames
CONTROL_PLANE_HOSTNAME="talos-cp-01"
WORKER1_HOSTNAME="talos-wk-01"
WORKER2_HOSTNAME="talos-wk-02"

# Terraform outputs file
TERRAFORM_OUTPUTS="${SCRIPT_DIR}/../ansible/terraform_outputs.json"

# IP addresses - will be loaded from Terraform outputs
CONTROL_PLANE_IP=""
WORKER1_IP=""
WORKER2_IP=""

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
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                    LAYER 3 - KUBERNETES                      ║
║                   Talos Linux Cluster Setup                  ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

load_terraform_outputs() {
    log "Loading Terraform outputs..."
    
    if [ ! -f "${TERRAFORM_OUTPUTS}" ]; then
        log_error "Terraform outputs file not found: ${TERRAFORM_OUTPUTS}"
        log_error "Please run Terraform apply first to generate outputs"
        exit 1
    fi
    
    # Extract IPs from Terraform outputs
    CONTROL_PLANE_IP=$(jq -r '.talos_ips.value["talos-cp-01"] // empty' "${TERRAFORM_OUTPUTS}")
    WORKER1_IP=$(jq -r '.talos_ips.value["talos-wk-01"] // empty' "${TERRAFORM_OUTPUTS}")
    WORKER2_IP=$(jq -r '.talos_ips.value["talos-wk-02"] // empty' "${TERRAFORM_OUTPUTS}")
    
    if [ -z "$CONTROL_PLANE_IP" ] || [ -z "$WORKER1_IP" ] || [ -z "$WORKER2_IP" ]; then
        log_error "Failed to extract Talos node IPs from Terraform outputs"
        log_error "Control Plane: ${CONTROL_PLANE_IP:-not found}"
        log_error "Worker 1: ${WORKER1_IP:-not found}"
        log_error "Worker 2: ${WORKER2_IP:-not found}"
        exit 1
    fi
    
    log "✓ Loaded Talos node IPs from Terraform:"
    log "  • Control Plane (${CONTROL_PLANE_HOSTNAME}): ${CONTROL_PLANE_IP}"
    log "  • Worker 1 (${WORKER1_HOSTNAME}): ${WORKER1_IP}"
    log "  • Worker 2 (${WORKER2_HOSTNAME}): ${WORKER2_IP}"
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first:"
        echo "sudo apt-get install -y jq"
        exit 1
    fi
    
    # Check if talosctl is installed
    if ! command -v talosctl &> /dev/null; then
        log_error "talosctl is not installed. Please install it first:"
        echo "curl -sL https://talos.dev/install | sh"
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first:"
        echo "https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
        exit 1
    fi
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed. Please install it first:"
        echo "https://helm.sh/docs/intro/install/"
        exit 1
    fi
    
    log "✓ All prerequisites are installed"
}

generate_talos_secrets() {
    log "Generating Talos secrets..."
    cd "${SCRIPT_DIR}"
    
    if [ -f "secrets.yaml" ]; then
        log_warning "secrets.yaml already exists, backing up..."
        mv secrets.yaml secrets.yaml.bak.$(date +%s)
    fi
    
    talosctl gen secrets
    log "✓ Talos secrets generated"
}

create_config_patches() {
    log "Creating configuration patches..."
    cd "${SCRIPT_DIR}"
    
    # VIP configuration for HA control plane
    cat > vip.yaml << EOF
machine:
  network:
    interfaces:
      - interface: eth0
        vip:
          ip: ${CLUSTER_VIP}
EOF
    
    # Allow control plane nodes to run workloads
    cat > allowcontrolplanes.yaml << EOF
cluster:
  allowSchedulingOnControlPlanes: true
EOF
    
    # CNI configuration (we'll use Cilium)
    cat > cni.yaml << EOF
cluster:
  network:
    cni:
      name: none
EOF
    
    # Kubernetes certificates configuration
    cat > kubernetes-certificates.yaml << EOF
cluster:
  apiServer:
    certSANs:
      - ${CLUSTER_VIP}
      - ${CONTROL_PLANE_IP}
      - homelab.local
      - homelab-k8s.local
EOF

    # Hostname patches for each node
    cat > controlplane-hostname.yaml << EOF
machine:
  network:
    hostname: ${CONTROL_PLANE_HOSTNAME}
EOF

    cat > worker1-hostname.yaml << EOF
machine:
  network:
    hostname: ${WORKER1_HOSTNAME}
EOF

    cat > worker2-hostname.yaml << EOF
machine:
  network:
    hostname: ${WORKER2_HOSTNAME}
EOF
    
    log "✓ Configuration patches created"
}

generate_talos_config() {
    log "Generating Talos configuration..."
    cd "${SCRIPT_DIR}"
    
    # Clean up previous configs
    rm -rf rendered/
    mkdir -p rendered/
    
    # Generate base configuration
    talosctl gen config ${CLUSTER_NAME} https://${CLUSTER_VIP}:6443 \
        --with-secrets secrets.yaml \
        --config-patch-control-plane @vip.yaml \
        --config-patch @allowcontrolplanes.yaml \
        --config-patch @cni.yaml \
        --config-patch @kubernetes-certificates.yaml \
        --output rendered
    
    # Apply hostname patches to each node config
    log_info "Applying hostname patches..."
    
    # Control plane with hostname
    talosctl gen config ${CLUSTER_NAME} https://${CLUSTER_VIP}:6443 \
        --with-secrets secrets.yaml \
        --config-patch-control-plane @vip.yaml \
        --config-patch @allowcontrolplanes.yaml \
        --config-patch @cni.yaml \
        --config-patch @kubernetes-certificates.yaml \
        --config-patch-control-plane @controlplane-hostname.yaml \
        --output rendered-cp
    
    # Worker 1 with hostname
    talosctl gen config ${CLUSTER_NAME} https://${CLUSTER_VIP}:6443 \
        --with-secrets secrets.yaml \
        --config-patch @allowcontrolplanes.yaml \
        --config-patch @cni.yaml \
        --config-patch @kubernetes-certificates.yaml \
        --config-patch-worker @worker1-hostname.yaml \
        --output rendered-w1
    
    # Worker 2 with hostname  
    talosctl gen config ${CLUSTER_NAME} https://${CLUSTER_VIP}:6443 \
        --with-secrets secrets.yaml \
        --config-patch @allowcontrolplanes.yaml \
        --config-patch @cni.yaml \
        --config-patch @kubernetes-certificates.yaml \
        --config-patch-worker @worker2-hostname.yaml \
        --output rendered-w2
    
    # Use the hostname-specific configs
    cp rendered-cp/controlplane.yaml rendered/controlplane.yaml
    cp rendered-w1/worker.yaml rendered/worker1.yaml
    cp rendered-w2/worker.yaml rendered/worker2.yaml
    
    log "✓ Talos configuration generated with hostnames"
}

apply_talos_config() {
    log "Applying Talos configuration to nodes..."
    cd "${SCRIPT_DIR}"
    
    log_info "Applying control plane configuration to ${CONTROL_PLANE_IP}..."
    talosctl apply-config --insecure --nodes ${CONTROL_PLANE_IP} --file rendered/controlplane.yaml
    
    log_info "Applying worker configuration to ${WORKER1_IP}..."
    talosctl apply-config --insecure --nodes ${WORKER1_IP} --file rendered/worker1.yaml
    
    log_info "Applying worker configuration to ${WORKER2_IP}..."
    talosctl apply-config --insecure --nodes ${WORKER2_IP} --file rendered/worker2.yaml
    
    log "✓ Talos configuration applied to all nodes"
    log_warning "Nodes are now rebooting and configuring themselves..."
    log_info "This may take 3-5 minutes. Please wait..."
    
    sleep 100  # Wait for nodes to reboot and configure
}

configure_talosctl() {
    log "Configuring talosctl client..."
    cd "${SCRIPT_DIR}"
    
    export TALOSCONFIG="${SCRIPT_DIR}/rendered/talosconfig"
    talosctl config endpoint ${CONTROL_PLANE_IP}
    talosctl config node ${CONTROL_PLANE_IP}
    
    log "✓ talosctl configured"
}

bootstrap_cluster() {
    log "Bootstrapping Kubernetes cluster..."
    cd "${SCRIPT_DIR}"
    
    export TALOSCONFIG="${SCRIPT_DIR}/rendered/talosconfig"
    
    # Wait for control plane to be ready
    log_info "Waiting for control plane to be ready..."
    timeout 100 bash -c 'until talosctl health --server=false 2>/dev/null; do sleep 10; done' || {
        log_error "Control plane failed to become ready"
        exit 1
    }
    
    # Bootstrap the cluster
    talosctl bootstrap
    
    # Generate kubeconfig
    talosctl kubeconfig rendered/kubeconfig
    
    log "✓ Kubernetes cluster bootstrapped"
}

wait_for_nodes() {
    log "Waiting for all nodes to be ready..."
    export KUBECONFIG="${SCRIPT_DIR}/rendered/kubeconfig"
    
    timeout 600 bash -c '
        until [ $(kubectl get nodes --no-headers 2>/dev/null | wc -l) -eq 3 ] && \
              kubectl get nodes --no-headers 2>/dev/null | grep -v Ready | wc -l | grep -q "^0$"; do
            echo "Waiting for nodes..."
            sleep 15
        done
    ' || {
        log_error "Nodes failed to become ready"
        kubectl get nodes
        exit 1
    }
    
    log "✓ All nodes are ready"
}

install_cilium() {
    log "Installing Cilium CNI..."
    export KUBECONFIG="${SCRIPT_DIR}/rendered/kubeconfig"
    
    # Add Cilium Helm repository
    helm repo add cilium https://helm.cilium.io/
    helm repo update
    
    # Install Cilium without kube-proxy replacement (more stable)
    helm install cilium cilium/cilium \
        --version 1.18.0 \
        --namespace kube-system \
        --set ipam.mode=kubernetes \
        --set kubeProxyReplacement=false \
        --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
        --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
        --set cgroup.autoMount.enabled=false \
        --set cgroup.hostRoot=/sys/fs/cgroup
    
    # Wait for Cilium to be ready
    log_info "Waiting for Cilium to be ready..."
    kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s
    
    log "✓ Cilium CNI installed and ready"
}

display_cluster_info() {
    log "Displaying cluster information..."
    export KUBECONFIG="${SCRIPT_DIR}/rendered/kubeconfig"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    CLUSTER DEPLOYMENT COMPLETE!              ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BLUE}🎉 Kubernetes Cluster Summary:${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    
    echo -e "${YELLOW}Cluster Details:${NC}"
    echo "  • Cluster Name: ${CLUSTER_NAME}"
    echo "  • Control Plane VIP: ${CLUSTER_VIP}:6443"
    echo "  • Kubeconfig: ${SCRIPT_DIR}/rendered/kubeconfig"
    echo "  • Talosconfig: ${SCRIPT_DIR}/rendered/talosconfig"
    echo ""
    
    echo -e "${YELLOW}Node Information:${NC}"
    kubectl get nodes -o wide
    echo ""
    
    echo -e "${YELLOW}System Pods Status:${NC}"
    kubectl get pods -n kube-system
    echo ""
    
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Export kubeconfig: export KUBECONFIG=${SCRIPT_DIR}/rendered/kubeconfig"
    echo "  2. Install ArgoCD: kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
    echo "  3. Configure storage classes and persistent volumes"
    echo "  4. Deploy homelab applications via GitOps"
}

# Main execution
main() {
    print_banner
    log "Starting Talos Linux Kubernetes cluster deployment..."
    echo ""
    
    check_prerequisites
    load_terraform_outputs
    generate_talos_secrets
    create_config_patches
    generate_talos_config
    apply_talos_config
    configure_talosctl
    bootstrap_cluster
    wait_for_nodes
    install_cilium
    display_cluster_info
    
    log "✅ Layer 3 - Kubernetes deployment completed successfully!"
}

# Execute main function
main "$@"