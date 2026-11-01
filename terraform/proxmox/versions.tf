terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    dns = {
      source  = "hashicorp/dns"
      version = "~> 3.4"
    }
  }
}
