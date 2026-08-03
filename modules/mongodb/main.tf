resource "azurerm_cosmosdb_account" "main" {
  name                 = "${var.name}-${var.env}"
  location             = var.rg_location
  resource_group_name  = var.rg_name
  offer_type           = "Standard"
  kind                 = "MongoDB"
  mongo_server_version = 7.0
}


