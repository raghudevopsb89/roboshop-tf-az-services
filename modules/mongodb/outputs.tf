output "endpoint" {
  value = azurerm_cosmosdb_account.main.endpoint
}

# Cosmos hands out one account-level connection string of the shape
#   mongodb://<acct>:<key>@<host>:10255/?ssl=true&...
# Each service needs its own database in the path, so splice the name in.
output "mongo_urls" {
  value = {
    for db in var.databases : db => replace(
      azurerm_cosmosdb_account.main.primary_mongodb_connection_string,
      "/?", "/${db}?"
    )
  }
  sensitive = true
}
