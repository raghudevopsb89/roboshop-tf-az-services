resource "azurerm_private_dns_zone" "mysql" {
  name                = "${var.name}-${var.env}private.mysql.database.azure.com"
  resource_group_name = var.rg_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "mysql" {
  name                 = "${var.name}-${var.env}-link"
  private_dns_zone_id  = azurerm_private_dns_zone.mysql.id
  virtual_network_id   = var.vnet_id
  registration_enabled = false
}

resource "azurerm_mysql_flexible_server" "main" {
  name                   = "${var.name}-${var.env}"
  resource_group_name    = var.rg_name
  location               = var.rg_location
  administrator_login    = data.azurerm_key_vault_secret.admin_username.value
  administrator_password = data.azurerm_key_vault_secret.admin_password.value
  backup_retention_days  = 7
  delegated_subnet_id    = var.subnet_id
  private_dns_zone_id    = azurerm_private_dns_zone.mysql.id
  sku_name               = var.sku_name

  depends_on = [azurerm_private_dns_zone_virtual_network_link.mysql]
}

resource "azurerm_mysql_flexible_database" "main" {
  for_each            = toset(var.databases)
  name                = each.value
  resource_group_name = var.rg_name
  server_name         = azurerm_mysql_flexible_server.main.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}
