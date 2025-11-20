terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
    }
  }
}

resource "proxmox_vm_qemu" "vm" {
  name        = var.vm_name
  target_node = var.target_node
  vm_state    = var.vm_state

  disks {
    ide {
      ide2 {
        cdrom {
          iso = var.iso
        }
      }
    }
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
      # Longhorn data disk (optional, controlled by longhorn_disk_size variable)
      dynamic "scsi1" {
        for_each = var.longhorn_disk_size != "" ? [1] : []
        content {
          disk {
            storage    = var.longhorn_storage
            size       = var.longhorn_disk_size
            cache      = "writeback"
            discard    = true
            iothread   = true
            emulatessd = true
          }
        }
      }
    }
  }

  network {
    id       = "0"
    bridge   = var.network_bridge
    model    = var.network_model
    macaddr  = var.mac_address
    firewall = var.firewall
  }

  cpu {
    cores   = var.cores
    sockets = var.sockets
    type    = var.cpu
  }

  memory = var.memory

  boot    = "order=scsi0;ide2"
  agent   = 0
  os_type = "linux"
  qemu_os = "l26"
  onboot  = true
  scsihw  = "virtio-scsi-pci"
  tags    = var.tags

  lifecycle {
    ignore_changes = [
      boot,
      network
    ]
  }
}