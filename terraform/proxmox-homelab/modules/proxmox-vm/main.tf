terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
    }
  }
}
resource "proxmox_vm_qemu" "vm" {
  target_node = var.target_node
  name        = var.vm_name
  onboot      = var.onboot
  clone       = var.clone
  boot        = var.boot_order
  full_clone  = var.full_clone
  agent       = var.agent
  cores       = var.cores
  sockets     = var.sockets
  memory      = var.memory
  balloon     = var.balloon
  scsihw      = var.scsihw
  tags        = var.tags
  vm_state    = var.vm_state

  network {
    id       = 0
    bridge   = var.network_bridge
    model    = var.network_model
    firewall = var.firewall
  }

  disks {
    scsi {
      scsi0 {
        disk {
          storage    = var.storage
          size       = var.disk_size
          cache      = var.disk_cache
          discard    = var.discard
          iothread   = var.iothread
          emulatessd = var.emulatessd
        }
      }
    }
    ide {
      ide0 {
        cloudinit {
          storage = var.cloudinit_storage
        }
      }
    }
  }

  os_type      = var.os_type
  ipconfig0    = var.ipconfig0
  nameserver   = var.nameserver
  searchdomain = var.searchdomain
  ciuser       = var.ciuser
  cipassword   = var.cipassword
  sshkeys      = <<EOF
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCo+YWXjytd2oSP8O7h4C8XBm1rwuMsWulsGLn/p1jJYXXnxfkVHJiBLCpiebDObRekCoWemjaWndC69lYiPeibIqy83tLhjjqljSrEbuZqvRyZIrLfTIwRSgIFLuH6DsKgPEZhnfv80U59vm0W/FHCN/HjZo9Qstu/NUwMW7JrgCxcfSBdz0o3b1H59+R+UpexuK3o2D/GEVVJJR848szKCxlIFGuftFYgigYJ6OWdtpoga/LJPOv0qJheZpwnZgYnIzkWfpbNO3RNUP7CaUTep+n+gEkdSQ8lzn5vs1seT8tqzOL7OExkcmLgch0/oE894J0oSF3NTQjSYPjt3sAxa3RDpDszkOkOVT1HJa0MQGdUJ1chuiz4ubezIPlsR21pTnYSNyGIn25g3IxckYrcJdCboWEVK3lkyfb5bWP7rfu/r6oaq2UWILjGbSXHknKuQ+HyojYbMusVkVNuuF8iSC/mJkETV16Ufy2NQ3BTBdn93urtU8kvVG7QcLZAVIs= jamil.shaikh@OPLPT069.local
    EOF 

  serial {
    id   = "0"
    type = "socket"
  }
}
