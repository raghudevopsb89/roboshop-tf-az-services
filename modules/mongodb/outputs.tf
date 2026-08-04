output "endpoint" {
  value = azurerm_cosmosdb_account.main.endpoint
}

output "mongo_urls" {
  value = {
    for db in var.databases : db => replace(
      azurerm_cosmosdb_account.main.primary_mongodb_connection_string,
      "/?", "/${db}?"
    )
  }
  sensitive = true
}
