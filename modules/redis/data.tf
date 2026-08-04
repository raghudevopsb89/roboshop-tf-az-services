data "azurerm_managed_redis" "main" {
  name                = azurerm_managed_redis.main.name
  resource_group_name = var.rg_name
}
