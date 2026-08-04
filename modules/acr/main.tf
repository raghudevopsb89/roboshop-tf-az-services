resource "azurerm_container_registry" "main" {
  name                = "${var.name}${var.env}"
  resource_group_name = var.rg_name
  location            = var.rg_location
  sku                 = var.sku
  admin_enabled       = false
}
