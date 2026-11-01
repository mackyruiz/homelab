provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_insecure_tls
  ssh {
    agent       = false
    username    = var.proxmox_ssh_username
    private_key = file(var.proxmox_ssh_private_key)
  }
}

# The live nas zone accepts updates signed with BIND's rndc-key (hmac-sha256).
provider "dns" {
  update {
    server        = var.dns_server
    key_name      = "rndc-key."
    key_algorithm = var.dns_tsig_key_algorithm
    key_secret    = var.dns_tsig_key_secret
  }
}
