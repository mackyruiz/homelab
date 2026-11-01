resource "proxmox_virtual_environment_file" "vendor_data" {
  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.node_name

  source_raw {
    file_name = "${var.vm_name}-vendor-data.yaml"
    data      = <<-EOF
      #cloud-config
      package_update: true
      packages:
        - qemu-guest-agent
      runcmd:
        - systemctl enable qemu-guest-agent
        - systemctl start qemu-guest-agent
      EOF
  }

  lifecycle {
    # Not returned by the API on import.
    ignore_changes = [source_raw]
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  name        = var.vm_name
  vm_id       = var.vm_id
  description = var.vm_description
  node_name   = var.node_name
  tags        = var.vm_tags
  started     = true

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_size_gb
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge  = var.network_bridge
    model   = "virtio"
    vlan_id = var.vlan_id == 0 ? null : var.vlan_id
  }

  initialization {
    datastore_id        = var.datastore_id
    vendor_data_file_id = proxmox_virtual_environment_file.vendor_data.id

    ip_config {
      ipv4 {
        address = var.ip_config
        gateway = var.ipv4_gateway
      }
    }

    dynamic "dns" {
      for_each = var.dns_domain != null ? [1] : []
      content {
        domain  = var.dns_domain
        servers = var.dns_servers
      }
    }

    user_account {
      username = var.user_name
      keys     = var.ssh_public_keys
    }
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  scsi_hardware = "virtio-scsi-single"

  lifecycle {
    # clone only matters at create time; importing a cloned VM would otherwise
    # force replacement (bpg/terraform-provider-proxmox#1988).
    ignore_changes = [clone]
  }
}
