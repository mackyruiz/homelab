variable "node_name" {
  type = string
}

variable "datastore_id" {
  type = string
}

variable "snippet_datastore_id" {
  type = string
}

variable "template_vm_id" {
  type = number
}

variable "vm_name" {
  type = string
}

variable "vm_description" {
  type = string
}

variable "vm_tags" {
  type = list(string)
}

variable "cpu_cores" {
  type = number
}

variable "memory_mb" {
  type = number
}

variable "disk_size_gb" {
  type = number
}

variable "network_bridge" {
  type = string
}

variable "vlan_id" {
  type = number
}

variable "user_name" {
  type = string
}

variable "ssh_public_keys" {
  type = list(string)
}

variable "ip_config" {
  type = string
}

variable "vm_id" {
  type    = number
  default = null
}

variable "ipv4_gateway" {
  type    = string
  default = null
}

variable "dns_domain" {
  type    = string
  default = null
}

variable "dns_servers" {
  type    = list(string)
  default = null
}
