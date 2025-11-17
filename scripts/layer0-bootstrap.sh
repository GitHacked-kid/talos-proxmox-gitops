#!/usr/bin/env bash

################################################################################
# Homelab Layer 0 - Bootstrap GitHub Runner
# 
# This script creates and configures a GitHub Actions self-hosted runner VM
# that will automate the entire homelab deployment via GitOps.
#
# The runner VM will have:
# - GitHub Actions Runner Agent
# - Docker & Docker Compose
# - Terraform
# - Ansible
# - talosctl
# - kubectl
# - helm
#
# Once configured, the runner will automatically deploy:
# - Layer 1: Infrastructure (Terraform)
# - Layer 2: Services (Ansible)
# - Layer 3: Kubernetes (Talos)
# - Layer 4: Applications (ArgoCD)
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROXMOX_HOST="${PROXMOX_HOST:-10.20.0.10}"
PROXMOX_USER="${PROXMOX_USER:-root}"
PROXMOX_NODE="${PROXMOX_NODE:-alif}"
PROXMOX_SSH_PORT="${PROXMOX_SSH_PORT:-22}"

# Runner VM Configuration
RUNNER_VM_ID=8000
RUNNER_VM_NAME="vm-github-runner"
RUNNER_IP="10.20.0.30/24"  # Initial static IP attempt (may not work, will discover via QEMU agent)
RUNNER_GATEWAY="10.20.0.1"
RUNNER_MEMORY=4096  # 4GB
RUNNER_CORES=2
RUNNER_DISK_SIZE="50G"
RUNNER_STORAGE="local-lvm"

# Template configuration
TEMPLATE_NAME="ubuntu-temp"
TEMPLATE_VM_ID=9000
UBUNTU_IMAGE_URL="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
IMAGE_FILE="ubuntu-24.04-server-cloudimg-amd64.img"
VM_USERNAME="ubuntu"
VM_PASSWORD="as"

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
║                   LAYER 0 - BOOTSTRAP                         ║
║               GitHub Actions Self-Hosted Runner               ║
║                                                               ║
║  This runner will automate your entire homelab via GitOps:   ║
║  • Layer 1: Infrastructure (Terraform)                       ║
║  • Layer 2: Services (Ansible)                               ║
║  • Layer 3: Kubernetes (Talos)                               ║
║  • Layer 4: Applications (ArgoCD)                            ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check SSH access
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" exit 2>/dev/null; then
        log_error "Cannot SSH to Proxmox server!"
        log_error "Run: ssh-copy-id ${PROXMOX_USER}@${PROXMOX_HOST}"
        exit 1
    fi
    
    # Check if ubuntu-temp template exists
    local template_exists=$(ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
        "qm list | grep '${TEMPLATE_NAME}' || echo 'notfound'")
    
    if [[ "$template_exists" == "notfound" ]]; then
        log_warning "ubuntu-temp template not found!"
        read -p "Would you like to create it now? (yes/no): " create_template
        if [[ "$create_template" == "yes" ]]; then
            create_ubuntu_template
        else
            log_error "Template is required to continue"
            exit 1
        fi
    fi
    
    log "✓ Prerequisites checked"
}

check_github_token() {
    log "Checking GitHub configuration..."
    
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log_error "GITHUB_TOKEN environment variable not set!"
        echo ""
        log_info "Please set your GitHub Personal Access Token:"
        echo "  export GITHUB_TOKEN='ghp_your_token_here'"
        echo ""
        log_info "Token requirements:"
        echo "  • repo (all)"
        echo "  • workflow"
        echo "  • admin:org (read:org) - if using organization"
        echo ""
        log_info "Create token at: https://github.com/settings/tokens"
        exit 1
    fi
    
    if [[ -z "${GITHUB_REPO:-}" ]]; then
        log_error "GITHUB_REPO environment variable not set!"
        echo ""
        log_info "Please set your GitHub repository:"
        echo "  export GITHUB_REPO='owner/repo'"
        echo ""
        exit 1
    fi
    
    log "✓ GitHub configuration set"
}

create_ubuntu_template() {
    log "Creating Ubuntu 24.04 LTS cloud-init template ..."
    
    # Check if template already exists
    local template_exists=$(ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
        "qm list | grep '${TEMPLATE_VM_ID}' || echo 'notfound'")
    
    if [[ "$template_exists" != "notfound" ]]; then
        log_warning "Template already exists (ID: ${TEMPLATE_VM_ID})"
        read -p "Do you want to destroy and recreate it? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            log_info "Destroying existing template..."
            ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
                "qm destroy ${TEMPLATE_VM_ID}"
        else
            log "Keeping existing template"
            return 0
        fi
    fi
    
    # Get SSH public key
    if [[ ! -f ~/.ssh/id_rsa.pub ]]; then
        log_error "SSH public key not found at ~/.ssh/id_rsa.pub"
        exit 1
    fi
    local ssh_key=$(cat ~/.ssh/id_rsa.pub)
    
    log_info "Downloading Ubuntu 24.04 cloud image and creating template..."
    
    ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" bash << EOF
set -e

cd /var/lib/vz/template/iso

# Download Ubuntu cloud image
rm -f ${IMAGE_FILE}*
echo "Downloading Ubuntu 24.04 LTS cloud image..."
wget -q --show-progress "${UBUNTU_IMAGE_URL}" -O ${IMAGE_FILE}

# Install libguestfs-tools for virt-customize
apt-get update
apt-get install -y libguestfs-tools

# Customize the image to install qemu-guest-agent and configure passwordless sudo
echo "Customizing image with qemu-guest-agent and passwordless sudo..."
virt-customize -a ${IMAGE_FILE} \
    --install qemu-guest-agent \
    --run-command 'echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-ubuntu-nopasswd' \
    --run-command 'chmod 440 /etc/sudoers.d/99-ubuntu-nopasswd'

# Create VM
qm create ${TEMPLATE_VM_ID} \
    --name ${TEMPLATE_NAME} \
    --memory 2048 \
    --cores 2 \
    --net0 virtio,bridge=vmbr0 \
    --ostype l26

# Import disk
qm importdisk ${TEMPLATE_VM_ID} ${IMAGE_FILE} ${RUNNER_STORAGE}

# Attach disk as scsi0
qm set ${TEMPLATE_VM_ID} --scsihw virtio-scsi-pci --scsi0 ${RUNNER_STORAGE}:vm-${TEMPLATE_VM_ID}-disk-0

# Add cloud-init drive
qm set ${TEMPLATE_VM_ID} --ide2 ${RUNNER_STORAGE}:cloudinit

# Make boot from the image
qm set ${TEMPLATE_VM_ID} --boot c --bootdisk scsi0

# Add serial console
qm set ${TEMPLATE_VM_ID} --serial0 socket --vga serial0

# Enable QEMU guest agent
qm set ${TEMPLATE_VM_ID} --agent enabled=1

# Set DHCP
qm set ${TEMPLATE_VM_ID} --ipconfig0 ip=dhcp

# Set user, password and SSH key
qm set ${TEMPLATE_VM_ID} --ciuser ${VM_USERNAME}
qm set ${TEMPLATE_VM_ID} --cipassword ${VM_PASSWORD}
qm set ${TEMPLATE_VM_ID} --sshkeys <(echo "${ssh_key}")

# Set nameserver
qm set ${TEMPLATE_VM_ID} --nameserver 8.8.8.8

# Convert to template
qm template ${TEMPLATE_VM_ID}

# Cleanup
rm -f ${IMAGE_FILE}

echo "✓ Template created successfully"
EOF
    
    log "✓ Ubuntu 24.04 LTS template created "
    log_info "Template ID: ${TEMPLATE_VM_ID}, Name: ${TEMPLATE_NAME}"
    log_info "Username: ${VM_USERNAME}, Password: ${VM_PASSWORD}, SSH key configured"
}

create_runner_vm() {
    log "Creating GitHub Runner VM..."
    
    # Check if VM already exists
    local vm_exists=$(ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
        "qm list | grep '${RUNNER_VM_ID}' || echo 'notfound'")
    
    if [[ "$vm_exists" != "notfound" ]]; then
        log_warning "Runner VM already exists (ID: ${RUNNER_VM_ID})"
        read -p "Do you want to destroy and recreate it? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            log_info "Destroying existing VM..."
            ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
                "qm stop ${RUNNER_VM_ID} || true; qm destroy ${RUNNER_VM_ID}"
        else
            log "Keeping existing VM, skipping creation"
            return 0
        fi
    fi
    
    log_info "Cloning VM from ${TEMPLATE_NAME}..."
    
    ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" bash << EOF
set -e

# Get template VM ID
TEMPLATE_ID=\$(qm list | grep '${TEMPLATE_NAME}' | awk '{print \$1}')

# Clone from template
qm clone \$TEMPLATE_ID ${RUNNER_VM_ID} --name ${RUNNER_VM_NAME} --full

# Configure VM
qm set ${RUNNER_VM_ID} --memory ${RUNNER_MEMORY}
qm set ${RUNNER_VM_ID} --cores ${RUNNER_CORES}
qm set ${RUNNER_VM_ID} --cpu host
qm set ${RUNNER_VM_ID} --onboot 1
qm set ${RUNNER_VM_ID} --agent enabled=1
qm set ${RUNNER_VM_ID} --tags github-runner,automation,layer0

# Resize disk if needed
qm resize ${RUNNER_VM_ID} scsi0 ${RUNNER_DISK_SIZE}

# Configure network with static IP
qm set ${RUNNER_VM_ID} --ipconfig0 "ip=${RUNNER_IP},gw=${RUNNER_GATEWAY}"
qm set ${RUNNER_VM_ID} --nameserver ${RUNNER_GATEWAY}

# Start VM
qm start ${RUNNER_VM_ID}

echo "Waiting for VM to boot..."
sleep 30
EOF
    
    log "✓ Runner VM created and started"
}


wait_for_ssh() {
    log "Waiting for SSH access to runner VM..."
    
    local runner_ip=$(echo ${RUNNER_IP} | cut -d'/' -f1)
    
    # Remove old host key if exists
    ssh-keygen -f ~/.ssh/known_hosts -R ${runner_ip} 2>/dev/null || true
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            ubuntu@${runner_ip} exit 2>/dev/null; then
            log "✓ SSH access established to ${runner_ip}"
            # Add the new host key
            ssh-keyscan -H ${runner_ip} >> ~/.ssh/known_hosts 2>/dev/null
            return 0
        fi
        
        log_info "Attempt $attempt/$max_attempts - waiting for SSH..."
        sleep 10
        ((attempt++))
    done
    
    log_error "Failed to establish SSH connection after $max_attempts attempts"
    exit 1
}

configure_runner_basic() {
    log "Configuring runner VM (basic setup)..."
    
    local runner_ip=$(echo ${RUNNER_IP} | cut -d'/' -f1)
    
    # Copy SSH key if not already present
    ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${runner_ip} 2>/dev/null || true
    
    ssh -o StrictHostKeyChecking=no ubuntu@${runner_ip} bash << 'EOF'
set -e

# Update system
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install basic tools
sudo apt-get install -y \
    curl wget git vim nano \
    ca-certificates gnupg lsb-release \
    software-properties-common \
    apt-transport-https \
    jq unzip

echo "Basic setup complete"
EOF
    
    log "✓ Basic configuration complete"
}

install_nodejs() {
    log "Installing Node.js..."
    
    local runner_ip=$(echo ${RUNNER_IP} | cut -d'/' -f1)
    
    # Check if Node.js is already installed
    if ssh ubuntu@${runner_ip} command -v node >/dev/null 2>&1; then
        local node_version=$(ssh ubuntu@${runner_ip} node --version)
        log "✓ Node.js ${node_version} is already installed, skipping installation"
        return 0
    fi
    
    ssh ubuntu@${runner_ip} bash << 'EOF'
set -e

# Install Node.js LTS (v20.x)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
echo "Node.js $(node --version) installed"
echo "npm $(npm --version) installed"
EOF
    
    log "✓ Node.js installed"
}

install_docker() {
    log "Installing Docker..."
    
    local runner_ip=$(echo ${RUNNER_IP} | cut -d'/' -f1)
    
    # Check if Docker is already installed
    if ssh ubuntu@${runner_ip} command -v docker >/dev/null 2>&1; then
        log "✓ Docker is already installed, skipping installation"
        return 0
    fi
    
    ssh ubuntu@${runner_ip} bash << 'EOF'
set -e

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
rm get-docker.sh

# Add user to docker group
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Start Docker
sudo systemctl enable docker
sudo systemctl start docker

echo "Docker installed successfully"
EOF
    
    log "✓ Docker installed"
}

install_terraform() {
    log "Installing Terraform..."
    
    local runner_ip=$(echo ${RUNNER_IP} | cut -d'/' -f1)
    
    # Check if Terraform is already installed
    if ssh ubuntu@${runner_ip} command -v terraform >/dev/null 2>&1; then
        local tf_version=$(ssh ubuntu@${runner_ip} terraform version -json | jq -r '.terraform_version')
        log "✓ Terraform ${tf_version} is already installed, skipping installation"
        return 0
    fi
    
    ssh ubuntu@${runner_ip} bash << 'EOF'
set -e

# Install Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update
sudo apt-get install -y terraform

echo "Terraform $(terraform version | head -1) installed"
EOF
    
    log "✓ Terraform installed"
}

install_ansible() {
    log "Installing Ansible..."
    
    local runner_ip=$(echo ${RUNNER_IP} | cut -d'/' -f1)
    
    # Check if Ansible is already installed
    if ssh ubuntu@${runner_ip} command -v ansible >/dev/null 2>&1; then
        local ansible_version=$(ssh ubuntu@${runner_ip} ansible --version | head -1 | awk '{print $2}')
        log "✓ Ansible ${ansible_version} is already installed, skipping installation"
        return 0
    fi
    
    ssh ubuntu@${runner_ip} bash << 'EOF'
set -e

# Install Ansible from Ubuntu repository (recommended for Ubuntu 24.04)
sudo apt-get update
sudo apt-get install -y ansible

# Alternatively, use pipx for latest version
# sudo apt-get install -y pipx
# pipx install --include-deps ansible

echo "Ansible $(ansible --version | head -1) installed"
EOF
    
    log "✓ Ansible installed"
}

install_kubernetes_tools() {
    log "Installing Kubernetes tools (kubectl, helm, talosctl)..."
    
    local runner_ip=$(echo ${RUNNER_IP} | cut -d'/' -f1)
    
    # Check if tools are already installed
    local kubectl_installed=$(ssh ubuntu@${runner_ip} command -v kubectl >/dev/null 2>&1 && echo "yes" || echo "no")
    local helm_installed=$(ssh ubuntu@${runner_ip} command -v helm >/dev/null 2>&1 && echo "yes" || echo "no")
    local talosctl_installed=$(ssh ubuntu@${runner_ip} command -v talosctl >/dev/null 2>&1 && echo "yes" || echo "no")
    
    if [[ "$kubectl_installed" == "yes" && "$helm_installed" == "yes" && "$talosctl_installed" == "yes" ]]; then
        log "✓ Kubernetes tools are already installed, skipping installation"
        return 0
    fi
    
    ssh ubuntu@${runner_ip} bash << 'EOF'
set -e

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "Detected architecture: $ARCH"

# Install kubectl if not present
if ! command -v kubectl >/dev/null 2>&1; then
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
fi

# Install helm if not present
if ! command -v helm >/dev/null 2>&1; then
    echo "Installing helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Install talosctl if not present
if ! command -v talosctl >/dev/null 2>&1; then
    echo "Installing talosctl for ${ARCH}..."
    TALOS_VERSION=$(curl -s https://api.github.com/repos/siderolabs/talos/releases/latest | grep tag_name | cut -d '"' -f 4)
    curl -Lo /tmp/talosctl "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-linux-${ARCH}"
    sudo install -o root -g root -m 0755 /tmp/talosctl /usr/local/bin/talosctl
    rm /tmp/talosctl
fi

echo "Kubernetes tools installed:"
echo "  kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
echo "  helm: $(helm version --short)"
echo "  talosctl: $(talosctl version --client --short 2>/dev/null || talosctl version --client)"
EOF
    
    log "✓ Kubernetes tools installed"
}

remove_existing_github_runner() {
    log "Checking for existing GitHub runner with name ${RUNNER_VM_NAME}..."
    
    # Get list of runners
    local runner_id=$(curl -s \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${GITHUB_REPO}/actions/runners" | \
        jq -r ".runners[] | select(.name==\"${RUNNER_VM_NAME}\") | .id")
    
    if [[ -n "$runner_id" && "$runner_id" != "null" ]]; then
        log_warning "Found existing runner with ID: ${runner_id}"
        log_info "Removing existing runner from GitHub..."
        
        curl -s -X DELETE \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/${runner_id}"
        
        log "✓ Existing runner removed from GitHub"
        sleep 3
    else
        log "✓ No existing runner found with name ${RUNNER_VM_NAME}"
    fi
}

install_github_runner() {
    log "Installing GitHub Actions Runner..."
    
    local runner_ip=$(echo ${RUNNER_IP} | cut -d'/' -f1)
    
    # Check if runner is already installed and running
    if ssh ubuntu@${runner_ip} "[ -d ~/actions-runner ] && sudo systemctl is-active --quiet actions.runner.* 2>/dev/null"; then
        log "✓ GitHub Actions Runner is already installed and running, skipping installation"
        return 0
    fi
    
    # Remove existing runner from GitHub if it exists
    remove_existing_github_runner
    
    # Get registration token from GitHub
    log_info "Getting runner registration token from GitHub..."
    local reg_token=$(curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token" | jq -r .token)
    
    if [[ -z "$reg_token" || "$reg_token" == "null" ]]; then
        log_error "Failed to get registration token from GitHub"
        exit 1
    fi
    
    ssh ubuntu@${runner_ip} bash << EOF
set -e

# Create runner directory
mkdir -p ~/actions-runner
cd ~/actions-runner

# Download latest runner
RUNNER_VERSION=\$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/v//')
curl -o actions-runner-linux-x64.tar.gz -L \
    "https://github.com/actions/runner/releases/download/v\${RUNNER_VERSION}/actions-runner-linux-x64-\${RUNNER_VERSION}.tar.gz"

# Extract runner
tar xzf ./actions-runner-linux-x64.tar.gz
rm actions-runner-linux-x64.tar.gz

# Configure runner
./config.sh --unattended \
    --url "https://github.com/${GITHUB_REPO}" \
    --token "${reg_token}" \
    --name "${RUNNER_VM_NAME}" \
    --labels "self-hosted,homelab,proxmox" \
    --work "_work"

# Install as service
sudo ./svc.sh install
sudo ./svc.sh start

echo "GitHub Runner installed and started as service"
EOF
    
    log "✓ GitHub Actions Runner installed and configured"
}

configure_proxmox_ssh_access() {
    log "Configuring SSH access from runner to Proxmox host..."
    
    local runner_ip=$(echo ${RUNNER_IP} | cut -d'/' -f1)
    
    # Check if SSH private key exists
    if [[ ! -f ~/.ssh/id_rsa ]]; then
        log_error "SSH private key not found at ~/.ssh/id_rsa"
        log_error "The runner needs this key to SSH to Proxmox"
        exit 1
    fi
    
    # First, ensure the SSH key is authorized on Proxmox for root user
    log_info "Authorizing runner's SSH key on Proxmox host..."
    if ! ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" "grep -q \"$(cat ~/.ssh/id_rsa.pub)\" ~/.ssh/authorized_keys 2>/dev/null"; then
        ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
            "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys" < ~/.ssh/id_rsa.pub
        ssh "${PROXMOX_USER}@${PROXMOX_HOST}" -p "${PROXMOX_SSH_PORT}" \
            "chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
        log_info "✓ SSH key added to Proxmox authorized_keys"
    else
        log_info "✓ SSH key already authorized on Proxmox"
    fi
    
    # Copy SSH private key to runner VM
    log_info "Copying SSH key to runner VM..."
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/.ssh/id_rsa ubuntu@${runner_ip}:~/.ssh/id_rsa
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/.ssh/id_rsa.pub ubuntu@${runner_ip}:~/.ssh/id_rsa.pub
    
    # Configure SSH on runner VM
    ssh -o StrictHostKeyChecking=no ubuntu@${runner_ip} bash << EOF
set -e

# Set proper permissions on SSH key
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub

# Add Proxmox host to known_hosts
ssh-keyscan -H ${PROXMOX_HOST} >> ~/.ssh/known_hosts 2>/dev/null || true

# Test SSH connection to Proxmox
if ssh -o BatchMode=yes -o ConnectTimeout=5 ${PROXMOX_USER}@${PROXMOX_HOST} exit 2>/dev/null; then
    echo "✓ SSH connection to Proxmox successful"
else
    echo "⚠ Warning: Could not establish SSH connection to Proxmox"
    echo "  Make sure the SSH key is authorized on Proxmox host"
fi
EOF
    
    log "✓ Proxmox SSH access configured"
}

setup_runner_workspace() {
    log "Setting up runner workspace..."
    
    local runner_ip=$(echo ${RUNNER_IP} | cut -d'/' -f1)
    
    ssh ubuntu@${runner_ip} bash << EOF
set -e

# Create workspace directory
mkdir -p ~/homelab-workspace

# Clone repository (will be done by GitHub Actions, but prepare the structure)
cd ~/homelab-workspace

# Create necessary directories
mkdir -p terraform ansible talos gitops

echo "Runner workspace prepared"
EOF
    
    log "✓ Runner workspace setup complete"
}

create_inventory_for_runner() {
    log "Creating Ansible inventory for runner management..."
    
    local runner_ip=$(echo ${RUNNER_IP} | cut -d'/' -f1)
    
    mkdir -p ../../ansible/inventory
    
    cat > ../../ansible/inventory/runner.yml << EOF
# GitHub Runner VM Inventory
all:
  hosts:
    github-runner:
      ansible_host: ${runner_ip}
      ansible_user: ubuntu
      ansible_become: yes
      ansible_python_interpreter: /usr/bin/python3
  
  vars:
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
EOF
    
    log "✓ Ansible inventory created at ansible/inventory/runner.yml"
}

display_summary() {
    local runner_ip=$(echo ${RUNNER_IP} | cut -d'/' -f1)
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          LAYER 0 - GITHUB RUNNER BOOTSTRAP COMPLETE!         ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BLUE}📊 Runner VM Details:${NC}"
    echo "  • VM ID: ${RUNNER_VM_ID}"
    echo "  • VM Name: ${RUNNER_VM_NAME}"
    echo "  • IP Address: ${runner_ip}"
    echo "  • Memory: ${RUNNER_MEMORY}MB"
    echo "  • Cores: ${RUNNER_CORES}"
    echo "  • Storage: ${RUNNER_DISK_SIZE}"
    echo ""
    
    echo -e "${BLUE}🔧 Installed Tools:${NC}"
    echo "  ✓ Node.js & npm"
    echo "  ✓ Docker & Docker Compose"
    echo "  ✓ Terraform"
    echo "  ✓ Ansible"
    echo "  ✓ kubectl"
    echo "  ✓ helm"
    echo "  ✓ talosctl"
    echo "  ✓ GitHub Actions Runner"
    echo ""
    
    echo -e "${BLUE}🔐 SSH Configuration:${NC}"
    echo "  ✓ SSH key copied to runner"
    echo "  ✓ Proxmox host added to known_hosts"
    echo "  ✓ Runner can SSH to ${PROXMOX_HOST}"
    echo ""
    
    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo "  1. Verify runner in GitHub:"
    echo "     https://github.com/${GITHUB_REPO}/settings/actions/runners"
    echo ""
    echo "  2. Push your code to trigger GitHub Actions workflow"
    echo ""
    echo "  3. Monitor runner logs:"
    echo "     ssh ubuntu@${runner_ip}"
    echo "     cd ~/actions-runner"
    echo "     tail -f _diag/Runner_*.log"
    echo ""
    
    echo -e "${YELLOW}💡 GitOps Workflow:${NC}"
    echo "  • Push to main branch → GitHub Actions triggers"
    echo "  • Runner deploys Layer 1 (Terraform)"
    echo "  • Runner deploys Layer 2 (Ansible)"
    echo "  • Runner deploys Layer 3 (Talos K8s)"
    echo "  • ArgoCD manages Layer 4 (Applications)"
    echo ""
}

# Main execution
main() {
    print_banner
    
    log "Starting Layer 0 - GitHub Runner Bootstrap..."
    echo ""
    
    check_prerequisites
    check_github_token
    create_runner_vm
    wait_for_ssh
    configure_runner_basic
    install_nodejs
    install_docker
    install_terraform
    install_ansible
    install_kubernetes_tools
    install_github_runner
    configure_proxmox_ssh_access
    setup_runner_workspace
    create_inventory_for_runner
    display_summary
    
    log "✅ Layer 0 bootstrap completed successfully!"
}

# Run main function
main "$@"
