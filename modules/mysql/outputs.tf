output "host" {
  value = azurerm_mysql_flexible_server.main.fqdn
}

output "admin_username" {
  value = data.azurerm_key_vault_secret.admin_username.value
}

output "admin_password" {
  value     = data.azurerm_key_vault_secret.admin_password.value
  sensitive = true
}

output "databases" {
  value = [for d in azurerm_mysql_flexible_database.main : d.name]
}
