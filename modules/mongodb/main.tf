resource "azurerm_cosmosdb_account" "main" {
  name                 = "${var.name}-${var.env}"
  location             = var.rg_location
  resource_group_name  = var.rg_name
  offer_type           = "Standard"
  kind                 = "MongoDB"
  mongo_server_version = "7.0"

  consistency_policy {
    consistency_level = "Strong"
  }

  geo_location {
    location          = var.rg_location
    failover_priority = 0
  }
}

# One database per consuming service: user -> users, orders -> orders.
resource "azurerm_cosmosdb_mongo_database" "main" {
  for_each            = toset(var.databases)
  name                = each.value
  resource_group_name = var.rg_name
  account_name        = azurerm_cosmosdb_account.main.name
  throughput          = 400
}

# Cosmos rejects any query that sorts on an unindexed field with
# "The index path corresponding to the specified order-by item is excluded",
# so the collections are declared here with the indexes the services query on
# rather than being auto-created on first write.
resource "azurerm_cosmosdb_mongo_collection" "main" {
  for_each            = var.collections
  name                = each.value.name
  resource_group_name = var.rg_name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = each.value.database

  dynamic "index" {
    for_each = each.value.indexes
    content {
      keys   = index.value.keys
      unique = index.value.unique
    }
  }

  depends_on = [azurerm_cosmosdb_mongo_database.main]
}
