output "ubuntu_template_vm_id" {
  value       = module.ubuntu_template.template_vm_id
  description = "VMID of the Ubuntu 24.04 cloud-image template."
}

output "yarr_vm_id" {
  value       = module.yarr_vm.vm_id
  description = "VMID of the yarr media VM."
}

output "yarr_ipv4" {
  value       = module.yarr_vm.ipv4_address
  description = "DHCP address of the yarr VM (from the guest agent)."
}

output "debian_template_vm_id" {
  value       = module.debian_template.template_vm_id
  description = "VMID of the Debian 13 cloud-image template."
}

output "labtest_ipv4" {
  value       = var.labtest_enabled ? module.labtest_vm[0].ipv4_address : null
  description = "DHCP address of the labtest VM, when enabled."
}

output "almalinux_template_vm_id" {
  value       = module.almalinux_template.template_vm_id
  description = "VMID of the AlmaLinux 10 cloud-image template."
}

output "identity_vm_ids" {
  value       = { for k, m in module.identity_vm : k => m.vm_id }
  description = "VMIDs of the Stage 2 identity VMs."
}
