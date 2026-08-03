data "azurerm_key_vault_secret" "admin_username" {
  name         = "mysql-svc-username"
  key_vault_id = "/subscriptions/3f2e42e1-ca06-4a99-8c56-be8d8ba306db/resourceGroups/denmark-east-rg/providers/Microsoft.KeyVault/vaults/roboshopb89"
}

data "azurerm_key_vault_secret" "admin_password" {
  name         = "mysql-svc-password"
  key_vault_id = "/subscriptions/3f2e42e1-ca06-4a99-8c56-be8d8ba306db/resourceGroups/denmark-east-rg/providers/Microsoft.KeyVault/vaults/roboshopb89"
}

