# LXC Containers Configuration
# All services moved to Kubernetes or CasaOS
# - Redis: Running in Talos cluster
# - Pi-hole: Running on CasaOS media server

# No LXC containers needed anymore
locals {
  lxc_containers = {}
}

# Keeping resource definition for backward compatibility
resource "proxmox_lxc" "containers" {
  for_each = local.lxc_containers

  target_node  = each.value.target_node
  hostname     = each.value.hostname
  ostemplate   = each.value.template
  password     = "ubuntu"
  unprivileged = true
  onboot       = true
  start        = true
  tags         = each.value.tags

  cores = each.value.cores

  memory = each.value.memory
  swap   = each.value.swap

  rootfs {
    storage = each.value.storage
    size    = "${each.value.disk_size}G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = lookup(each.value, "ip", "dhcp")
    gw     = lookup(each.value, "gateway", null)
  }

  ssh_public_keys = <<-EOF
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCo+YWXjytd2oSP8O7h4C8XBm1rwuMsWulsGLn/p1jJYXXnxfkVHJiBLCpiebDObRekCoWemjaWndC69lYiPeibIqy83tLhjjqljSrEbuZqvRyZIrLfTIwRSgIFLuH6DsKgPEZhnfv80U59vm0W/FHCN/HjZo9Qstu/NUwMW7JrgCxcfSBdz0o3b1H59+R+UpexuK3o2D/GEVVJJR848szKCxlIFGuftFYgigYJ6OWdtpoga/LJPOv0qJheZpwnZgYnIzkWfpbNO3RNUP7CaUTep+n+gEkdSQ8lzn5vs1seT8tqzOL7OExkcmLgch0/oE894J0oSF3NTQjSYPjt3sAxa3RDpDszkOkOVT1HJa0MQGdUJ1chuiz4ubezIPlsR21pTnYSNyGIn25g3IxckYrcJdCboWEVK3lkyfb5bWP7rfu/r6oaq2UWILjGbSXHknKuQ+HyojYbMusVkVNuuF8iSC/mJkETV16Ufy2NQ3BTBdn93urtU8kvVG7QcLZAVIs= jamil.shaikh@OPLPT069.local
  EOF

  features {
    nesting = true
  }

  lifecycle {
    ignore_changes = [
      network,
    ]
  }
}

# Outputs for LXC containers
output "lxc_containers_info" {
  description = "Information about all LXC containers"
  value = {
    for name in keys(proxmox_lxc.containers) : name => {
      id       = proxmox_lxc.containers[name].id
      hostname = proxmox_lxc.containers[name].hostname
      # IP will be assigned via DHCP
      vmid = proxmox_lxc.containers[name].vmid
    }
  }
}
