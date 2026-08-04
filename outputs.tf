# Everything the roboshop services need in order to connect. Secrets are marked
# sensitive — read them with `terraform output -json`.

output "mysql_host" {
  value = module.mysql-svc.host
}

output "mysql_admin_username" {
  # Sourced from Key Vault, so Terraform treats it as sensitive.
  value     = module.mysql-svc.admin_username
  sensitive = true
}

output "mysql_admin_password" {
  value     = module.mysql-svc.admin_password
  sensitive = true
}

output "redis_host" {
  value = module.redis-svc.host
}

output "redis_port" {
  value = module.redis-svc.port
}

output "redis_primary_access_key" {
  value     = module.redis-svc.primary_access_key
  sensitive = true
}

output "mongo_urls" {
  value     = module.mongodb-svc.mongo_urls
  sensitive = true
}

output "servicebus_hostname" {
  value = module.servicebus-svc.hostname
}

output "servicebus_connection_string" {
  value     = module.servicebus-svc.connection_string
  sensitive = true
}

output "acr_login_server" {
  value = module.acr-svc.login_server
}

output "aks_cluster_name" {
  value = module.aks-svc.name
}

output "aks_resource_group" {
  value = azurerm_resource_group.main.name
}
