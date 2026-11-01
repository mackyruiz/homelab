variable "proxmox_endpoint" {
  type        = string
  description = "Full Proxmox API endpoint."
  default     = "https://10.0.0.60:8006/api2/json"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "root@pam!terraform"
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  type        = string
  description = ""
  sensitive   = true
}

variable "proxmox_insecure_tls" {
  type        = bool
  description = "Skip TLS verification for Proxmox."
  default     = true
}

variable "proxmox_ssh_username" {
  type        = string
  description = "SSH username used by the Proxmox provider for disk import operations."
  default     = "root"
}

variable "proxmox_ssh_private_key" {
  type        = string
  description = "Path to a PEM-formatted SSH private key used by the Proxmox provider."
  default     = "~/.ssh/id_ed25519"
}

variable "proxmox_node_name" {
  type        = string
  description = "Target Proxmox node name."
  default     = "pve1"
}

variable "template_datastore_id" {
  type        = string
  description = "Proxmox datastore for ISO/cloud image files."
  default     = "local"
}

variable "snippet_datastore_id" {
  type        = string
  description = "Proxmox datastore for cloud-init snippets."
  default     = "local"
}

variable "vm_datastore_id" {
  type        = string
  description = "Proxmox datastore for VM disks."
  default     = "local-lvm"
}

variable "network_bridge" {
  type        = string
  description = "Proxmox network bridge for the VM NIC."
  default     = "vmbr0"
}

variable "vlan_id" {
  type        = number
  description = "Optional VLAN tag."
  default     = 0
}

variable "admin_user" {
  type        = string
  description = "Initial cloud-init user for VMs."
  default     = "labadmin"
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "SSH public keys injected via cloud-init into new VMs."
  default = [
    "ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY",
    "ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY",
    "ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY",
  ]
}

variable "labtest_enabled" {
  type        = bool
  description = "Create the disposable Stage 1 rebuild-test VM (VMID 900)."
  default     = false
}

variable "dns_server" {
  type        = string
  description = "Authoritative LAN DNS server that accepts RFC2136 updates."
  default     = "10.0.0.225"
}

variable "dns_zone" {
  type        = string
  description = "Zone that receives identity host records."
  default     = "example.com."
}

variable "dns_tsig_key_algorithm" {
  type        = string
  description = "TSIG algorithm of the BIND update key, e.g. hmac-sha256."
}

variable "dns_tsig_key_secret" {
  type        = string
  description = "TSIG secret of the BIND update key."
  sensitive   = true
}

variable "proxmox_oidc_client_secret" {
  type        = string
  description = "OIDC client secret shared with the Authentik Proxmox provider."
  sensitive   = true
}
