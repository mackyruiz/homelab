variable "node_name" {
  type = string
}

variable "datastore_id" {
  type = string
}

variable "vm_datastore_id" {
  type = string
}

variable "template_name" {
  type = string
}

variable "image_url" {
  type = string
}

variable "network_bridge" {
  type = string
}

variable "vm_id" {
  type    = number
  default = null
}

variable "tags" {
  type = list(string)
}

variable "image_file_name" {
  type    = string
  default = null
}

variable "disk_size_gb" {
  type    = number
  default = 8
}
