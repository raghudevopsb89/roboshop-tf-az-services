variable "name" {}
variable "rg_name" {}
variable "rg_location" {}
variable "subnet_id" {}
variable "vnet_id" {}
variable "sku_name" {}
variable "env" {}

variable "databases" {
  type    = list(string)
  default = []
}
