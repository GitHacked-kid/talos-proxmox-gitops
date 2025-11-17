output "vm_id" {
  value = proxmox_vm_qemu.vm.id
}

output "vm_name" {
  value = proxmox_vm_qemu.vm.name
}

output "vm_ipv4_addresses" {
  value = proxmox_vm_qemu.vm.default_ipv4_address
}

output "vm_ssh_host" {
  value = proxmox_vm_qemu.vm.ssh_host
}