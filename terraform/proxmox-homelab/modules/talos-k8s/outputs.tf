output "vm_id" {
  description = "The ID of the created VM"
  value       = proxmox_vm_qemu.vm.id
}

output "vm_name" {
  description = "The name of the created VM"
  value       = proxmox_vm_qemu.vm.name
}

output "vm_mac_address" {
  description = "The MAC address of the VM's network interface"
  value       = proxmox_vm_qemu.vm.network[0].macaddr
}

output "vm_target_node" {
  description = "The Proxmox node where the VM is deployed"
  value       = proxmox_vm_qemu.vm.target_node
}

output "vm_state" {
  description = "The current state of the VM"
  value       = proxmox_vm_qemu.vm.vm_state
}
