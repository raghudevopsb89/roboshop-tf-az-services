resource "azurerm_mysql_flexible_server" "main" {
  name                   = "${var.name}-${var.env}"
  resource_group_name    = var.rg_name
  location               = var.rg_location
  administrator_login    = data.azurerm_key_vault_secret.admin_username.value
  administrator_password = data.azurerm_key_vault_secret.admin_password.value
  backup_retention_days  = 7
  delegated_subnet_id    = var.subnet_id
  sku_name               = var.subnet_id
}


