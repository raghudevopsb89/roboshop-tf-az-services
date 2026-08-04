resource "azurerm_managed_redis" "main" {
  name                = "${var.name}-${var.env}"
  resource_group_name = var.rg_name
  location            = var.rg_location
  sku_name            = var.sku_name

  default_database {
    client_protocol                    = "Encrypted"
    access_keys_authentication_enabled = true
  }
}
