variable "target_node" {
  type        = string
  description = "The target Proxmox node where the VM will be created"
  default     = "fatimavilla"
}

variable "vm_name" {
  type        = string
  description = "The name of the VM"
}

variable "onboot" {
  type    = bool
  default = true
}

variable "clone" {
  type = string
}

variable "boot_order" {
  type    = string
  default = "order=scsi0;ide0"
}

variable "full_clone" {
  type    = bool
  default = true
}

variable "agent" {
  type    = number
  default = 0
}

variable "cores" {
  type    = number
  default = 1
}

variable "sockets" {
  type    = number
  default = 1
}

variable "cpu" {
  type    = string
  default = "x86-64-v2-AES"
}

variable "memory" {
  type    = number
  default = 1024
}

variable "balloon" {
  type    = number
  default = 0
}

variable "scsihw" {
  type    = string
  default = "virtio-scsi-pci"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "network_model" {
  type    = string
  default = "virtio"
}

variable "firewall" {
  type    = bool
  default = true
}

variable "storage" {
  type = string
}

variable "disk_size" {
  type    = string
  default = "25G"
}

variable "disk_cache" {
  type    = string
  default = "writeback"
}

variable "discard" {
  type    = bool
  default = false
}

variable "iothread" {
  type    = bool
  default = true
}

variable "emulatessd" {
  type    = bool
  default = true
}

variable "cloudinit_storage" {
  type = string
}

variable "os_type" {
  type    = string
  default = "cloud-init"
}

variable "ipconfig0" {
  type = string
}

variable "ciuser" {
  type    = string
  default = "ubuntu"
}

variable "cipassword" {
  type    = string
  default = "as"
}

variable "sshkeys" {
  type      = string
  sensitive = true
  default   = "valuessh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCo+YWXjytd2oSP8O7h4C8XBm1rwuMsWulsGLn/p1jJYXXnxfkVHJiBLCpiebDObRekCoWemjaWndC69lYiPeibIqy83tLhjjqljSrEbuZqvRyZIrLfTIwRSgIFLuH6DsKgPEZhnfv80U59vm0W/FHCN/HjZo9Qstu/NUwMW7JrgCxcfSBdz0o3b1H59+R+UpexuK3o2D/GEVVJJR848szKCxlIFGuftFYgigYJ6OWdtpoga/LJPOv0qJheZpwnZgYnIzkWfpbNO3RNUP7CaUTep+n+gEkdSQ8lzn5vs1seT8tqzOL7OExkcmLgch0/oE894J0oSF3NTQjSYPjt3sAxa3RDpDszkOkOVT1HJa0MQGdUJ1chuiz4ubezIPlsR21pTnYSNyGIn25g3IxckYrcJdCboWEVK3lkyfb5bWP7rfu/r6oaq2UWILjGbSXHknKuQ+HyojYbMusVkVNuuF8iSC/mJkETV16Ufy2NQ3BTBdn93urtU8kvVG7QcLZAVIs= jamil.shaikh@OPLPT069.local"
}

variable "nameserver" {
  type    = string
  default = ""
}

variable "searchdomain" {
  type    = string
  default = ""
}

variable "tags" {
}

variable "vm_state" {
  type    = string
  default = "running"
}