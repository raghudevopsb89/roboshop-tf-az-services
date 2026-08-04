resource "azurerm_managed_redis" "main" {
  name                = "${var.name}-${var.env}"
  resource_group_name = var.rg_name
  location            = var.rg_location
  sku_name            = var.sku_name

  default_database {
    # This cache is reachable on a public endpoint, so the wire must be
    # encrypted; the cart service connects with rediss:// + access key.
    client_protocol                    = "Encrypted"
    access_keys_authentication_enabled = true
  }
}
