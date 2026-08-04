variable "name" {}
variable "env" {}
variable "rg_name" {}
variable "rg_location" {}

variable "databases" {
  type    = list(string)
  default = []
}

variable "collections" {
  type = map(object({
    name     = string
    database = string
    indexes = list(object({
      keys   = list(string)
      unique = bool
    }))
  }))
  default = {}
}
