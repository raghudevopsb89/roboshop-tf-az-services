resource "azurerm_servicebus_namespace" "main" {
  name                = "${var.name}-${var.env}"
  location            = var.rg_location
  resource_group_name = var.rg_name
  sku                 = var.sku
}

# payment publishes order messages, orders consumes them. Without this queue
# both services fail at startup.
resource "azurerm_servicebus_queue" "main" {
  for_each     = toset(var.queues)
  name         = each.value
  namespace_id = azurerm_servicebus_namespace.main.id
}
