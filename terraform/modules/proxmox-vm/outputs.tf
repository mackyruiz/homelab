output "vm_name" {
  value = proxmox_virtual_environment_vm.vm.name
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.vm.vm_id
}

output "ipv4_address" {
  value = try([for i, n in proxmox_virtual_environment_vm.vm.network_interface_names :
    proxmox_virtual_environment_vm.vm.ipv4_addresses[i][0]
  if n != "lo" && length(proxmox_virtual_environment_vm.vm.ipv4_addresses[i]) > 0][0], null)
}
