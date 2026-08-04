resource "azurerm_servicebus_namespace" "main" {
  name                = "${var.name}-${var.env}"
  location            = var.rg_location
  resource_group_name = var.rg_name
  sku                 = var.sku
}

resource "azurerm_servicebus_queue" "main" {
  for_each     = toset(var.queues)
  name         = each.value
  namespace_id = azurerm_servicebus_namespace.main.id
}
