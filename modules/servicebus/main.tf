resource "azurerm_servicebus_namespace" "main" {
  name                = "${var.name}-${var.env}"
  location            = var.rg_location
  resource_group_name = var.rg_name
  sku                 = var.sku
}




