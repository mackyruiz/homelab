module "ubuntu_template" {
  source = "../modules/proxmox-template"

  node_name       = var.proxmox_node_name
  datastore_id    = var.template_datastore_id
  vm_datastore_id = var.vm_datastore_id
  network_bridge  = var.network_bridge

  vm_id         = 106
  template_name = "ubuntu-2404-cloudimg"
  image_url     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  tags          = ["cloud-init", "template", "ubuntu"]
}

module "yarr_vm" {
  source = "../modules/proxmox-vm"

  node_name            = var.proxmox_node_name
  datastore_id         = var.vm_datastore_id
  snippet_datastore_id = var.snippet_datastore_id
  network_bridge       = var.network_bridge
  vlan_id              = var.vlan_id

  vm_id          = 107
  vm_name        = "yarr"
  vm_description = "Media stack VM managed by Terraform and Ansible"
  vm_tags        = ["docker", "media", "terraform"]
  cpu_cores      = 4
  memory_mb      = 32768
  disk_size_gb   = 96
  ip_config      = "dhcp"
  user_name      = var.admin_user

  # Must match the key already in 107's cloud-init config: changing it re-runs
  # cloud-init and regenerates host keys. Ansible manages the real authorized_keys.
  ssh_public_keys = [
    "ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY",
  ]

  template_vm_id = module.ubuntu_template.template_vm_id
}

module "debian_template" {
  source = "../modules/proxmox-template"

  node_name       = var.proxmox_node_name
  datastore_id    = var.template_datastore_id
  vm_datastore_id = var.vm_datastore_id
  network_bridge  = var.network_bridge

  vm_id           = 9001
  template_name   = "debian-13-cloudimg"
  image_url       = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
  image_file_name = "debian-13-genericcloud-amd64.qcow2.img"
  tags            = ["cloud-init", "debian", "template"]
}

module "almalinux_template" {
  source = "../modules/proxmox-template"

  node_name       = var.proxmox_node_name
  datastore_id    = var.template_datastore_id
  vm_datastore_id = var.vm_datastore_id
  network_bridge  = var.network_bridge

  vm_id           = 9002
  template_name   = "almalinux-10-cloudimg"
  image_url       = "https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/AlmaLinux-10-GenericCloud-latest.x86_64.qcow2"
  image_file_name = "almalinux-10-genericcloud-amd64.qcow2.img"
  disk_size_gb    = 10
  tags            = ["almalinux", "cloud-init", "template"]
}

module "labtest_vm" {
  source = "../modules/proxmox-vm"
  count  = var.labtest_enabled ? 1 : 0

  node_name            = var.proxmox_node_name
  datastore_id         = var.vm_datastore_id
  snippet_datastore_id = var.snippet_datastore_id
  network_bridge       = var.network_bridge
  vlan_id              = var.vlan_id

  vm_id           = 900
  vm_name         = "labtest"
  vm_description  = "Stage 1 rebuild test VM"
  vm_tags         = ["debian", "terraform", "test"]
  cpu_cores       = 2
  memory_mb       = 2048
  disk_size_gb    = 16
  ip_config       = "dhcp"
  user_name       = var.admin_user
  ssh_public_keys = var.ssh_public_keys

  template_vm_id = module.debian_template.template_vm_id
}
