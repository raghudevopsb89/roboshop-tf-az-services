# The azurerm_managed_redis resource does not populate default_database's
# primary_access_key (it comes back empty), so read the key back via the data
# source. Referencing the resource name keeps the dependency ordering right.
data "azurerm_managed_redis" "main" {
  name                = azurerm_managed_redis.main.name
  resource_group_name = var.rg_name
}
