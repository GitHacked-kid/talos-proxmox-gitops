# ubuntu VM for NFS Server (Large storage for media)
module "ubuntu-nfs" {
  source = "./modules/proxmox-vm"

  vm_name           = "ubuntu-nfs"
  target_node       = "alif"
  clone             = "ubuntu-temp"
  memory            = 2048
  cores             = 2
  storage           = "local-lvm"
  cloudinit_storage = "local-lvm"
  disk_size         = "600G" # Large storage for media + backups
  tags              = "nfs;ubuntu;storage"
  onboot            = true
  agent             = 1

  # DHCP configuration - no static IPs
  ipconfig0  = "ip=10.20.0.44/24,gw=10.20.0.1"
  ciuser     = "ubuntu"
  cipassword = "as"
}

# ubuntu VM for Media Server (CasaOS + Jellyfin + qBittorrent)
module "ubuntu-media" {
  source = "./modules/proxmox-vm"

  vm_name           = "ubuntu-media"
  target_node       = "alif"
  clone             = "ubuntu-temp"
  memory            = 8192 # 8GB RAM for media transcoding
  cores             = 4    # 4 cores for better performance
  storage           = "local-lvm"
  cloudinit_storage = "local-lvm"
  disk_size         = "100G" # OS disk, media stored on NFS
  tags              = "media;casaos;jellyfin;qbittorrent"
  onboot            = true
  agent             = 1

  # Static IP configuration for media server
  ipconfig0  = "ip=10.20.0.45/24,gw=10.20.0.1"
  ciuser     = "ubuntu"
  cipassword = "as"
}

# Outputs for ubuntu VMs
output "nfs_vm_info" {
  description = "NFS VM information"
  value = {
    id   = module.ubuntu-nfs.vm_id
    name = module.ubuntu-nfs.vm_name
  }
}

output "media_vm_info" {
  description = "Media Server VM information"
  value = {
    id   = module.ubuntu-media.vm_id
    name = module.ubuntu-media.vm_name
  }
}