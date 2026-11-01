locals {
  identity_vms = {
    freeipa     = { vm_id = 301, ip = "10.0.0.31", cores = 2, memory_mb = 4096, disk_gb = 32, os = "almalinux", description = "FreeIPA: Linux users, groups, SSH, sudo", tags = ["freeipa", "identity", "terraform"] }
    authentik   = { vm_id = 302, ip = "10.0.0.32", cores = 2, memory_mb = 6144, disk_gb = 32, os = "debian", description = "Authentik SSO + PostgreSQL", tags = ["authentik", "docker", "identity", "terraform"] }
    vaultwarden = { vm_id = 303, ip = "10.0.0.33", cores = 1, memory_mb = 2048, disk_gb = 16, os = "debian", description = "Vaultwarden password manager", tags = ["docker", "identity", "terraform", "vaultwarden"] }
    caddy       = { vm_id = 304, ip = "10.0.0.34", cores = 1, memory_mb = 2048, disk_gb = 16, os = "debian", description = "Caddy reverse proxy (Let's Encrypt via GoDaddy DNS-01)", tags = ["caddy", "docker", "identity", "terraform"] }
  }
}

module "identity_vm" {
  source   = "../modules/proxmox-vm"
  for_each = local.identity_vms

  node_name            = var.proxmox_node_name
  datastore_id         = var.vm_datastore_id
  snippet_datastore_id = var.snippet_datastore_id
  network_bridge       = var.network_bridge
  vlan_id              = var.vlan_id

  vm_id          = each.value.vm_id
  vm_name        = each.key
  vm_description = each.value.description
  vm_tags        = each.value.tags
  cpu_cores      = each.value.cores
  memory_mb      = each.value.memory_mb
  disk_size_gb   = each.value.disk_gb

  ip_config    = "${each.value.ip}/24"
  ipv4_gateway = "10.0.0.1"
  dns_domain   = "example.com"
  dns_servers  = [var.dns_server]

  user_name       = var.admin_user
  ssh_public_keys = var.ssh_public_keys

  template_vm_id = each.value.os == "almalinux" ? module.almalinux_template.template_vm_id : module.debian_template.template_vm_id
}
