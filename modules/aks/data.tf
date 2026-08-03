data "azurerm_key_vault_secret" "ClientID" {
  name         = "externalDnsClientID"
  key_vault_id = "/subscriptions/3f2e42e1-ca06-4a99-8c56-be8d8ba306db/resourceGroups/denmark-east-rg/providers/Microsoft.KeyVault/vaults/roboshopb89"
}

data "azurerm_key_vault_secret" "ClientPassword" {
  name         = "ExternalDnsClientPassword"
  key_vault_id = "/subscriptions/3f2e42e1-ca06-4a99-8c56-be8d8ba306db/resourceGroups/denmark-east-rg/providers/Microsoft.KeyVault/vaults/roboshopb89"
}

data "azurerm_key_vault_secret" "PrometheusClientID" {
  name         = "PrometheusClientID"
  key_vault_id = "/subscriptions/3f2e42e1-ca06-4a99-8c56-be8d8ba306db/resourceGroups/denmark-east-rg/providers/Microsoft.KeyVault/vaults/roboshopb89"
}

data "azurerm_key_vault_secret" "PrometheusClientPassword" {
  name         = "PrometheusClientPassword"
  key_vault_id = "/subscriptions/3f2e42e1-ca06-4a99-8c56-be8d8ba306db/resourceGroups/denmark-east-rg/providers/Microsoft.KeyVault/vaults/roboshopb89"
}

data "azurerm_key_vault_secret" "ExternalSecretClientID" {
  name         = "externalSecretClientID"
  key_vault_id = "/subscriptions/3f2e42e1-ca06-4a99-8c56-be8d8ba306db/resourceGroups/denmark-east-rg/providers/Microsoft.KeyVault/vaults/roboshopb89"
}

data "azurerm_key_vault_secret" "ExternalSecretClientPassword" {
  name         = "ExternalSecretClientPassword"
  key_vault_id = "/subscriptions/3f2e42e1-ca06-4a99-8c56-be8d8ba306db/resourceGroups/denmark-east-rg/providers/Microsoft.KeyVault/vaults/roboshopb89"
}


