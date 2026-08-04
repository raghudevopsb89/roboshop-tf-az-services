output "host" {
  value = azurerm_managed_redis.main.hostname
}

output "port" {
  value = data.azurerm_managed_redis.main.default_database[0].port
}

output "primary_access_key" {
  value     = data.azurerm_managed_redis.main.default_database[0].primary_access_key
  sensitive = true
}
