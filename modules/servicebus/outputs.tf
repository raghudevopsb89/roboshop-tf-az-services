output "hostname" {
  value = azurerm_servicebus_namespace.main.endpoint
}

output "connection_string" {
  value     = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive = true
}

output "queues" {
  value = [for q in azurerm_servicebus_queue.main : q.name]
}
