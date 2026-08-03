resource "azurerm_managed_redis" "example" {
  name                = "${var.name}-${var.env}"
  resource_group_name = var.rg_name
  location            = var.rg_location
  sku_name            = var.sku_name
}


