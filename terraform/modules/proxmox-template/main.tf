resource "proxmox_virtual_environment_download_file" "cloud_image" {
  content_type = "iso"
  datastore_id = var.datastore_id
  node_name    = var.node_name
  url          = var.image_url
  file_name    = var.image_file_name
  # Do not re-download when the upstream "current" image is refreshed.
  overwrite = false

  lifecycle {
    # Not returned by the API on import; the image is already on disk.
    ignore_changes = [url]
  }
}

resource "proxmox_virtual_environment_vm" "template" {
  name      = var.template_name
  vm_id     = var.vm_id
  node_name = var.node_name
  tags      = var.tags

  template = true
  started  = false

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  disk {
    datastore_id = var.vm_datastore_id
    file_id      = proxmox_virtual_environment_download_file.cloud_image.id
    interface    = "scsi0"
    size         = var.disk_size_gb
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  initialization {
    datastore_id = var.vm_datastore_id
    interface    = "ide2"
  }

  scsi_hardware = "virtio-scsi-single"

  lifecycle {
    # Not returned by the API on import; the disk is already imported.
    ignore_changes = [disk[0].file_id]
  }
}
