resource "azurerm_resource_group" "main" {
  location = var.location
  name     = "${replace(lower(var.location), " ", "-")}-${var.env}"
}

resource "azurerm_virtual_network" "main" {
  name                = var.env
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.address_space
}

resource "azurerm_subnet" "main" {
  for_each             = var.subnets
  name                 = each.key
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [each.value["cidr"]]

  # Outer block iterates over each delegation item
  dynamic "delegation" {
    for_each = each.value["subnet_delegations"]
    content {
      name = delegation.value.name

      # Inner block sets the dynamic service delegation values
      service_delegation {
        name    = delegation.value.service_delegation_name
        actions = delegation.value.service_delegation_actions
      }
    }
  }

}

resource "azurerm_virtual_network_peering" "default-to-new" {
  name                      = "default2dev"
  resource_group_name       = "denmark-east-rg"
  virtual_network_name      = "workstation-vnet"
  remote_virtual_network_id = azurerm_virtual_network.main.id
}

resource "azurerm_virtual_network_peering" "dev-to-default" {
  name                      = "dev2default"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.main.name
  remote_virtual_network_id = "/subscriptions/3f2e42e1-ca06-4a99-8c56-be8d8ba306db/resourceGroups/denmark-east-rg/providers/Microsoft.Network/virtualNetworks/workstation-vnet"
}

module "mysql-svc" {
  source      = "./modules/mysql"
  name        = var.mysql-svc["name"]
  rg_location = azurerm_resource_group.main.location
  rg_name     = azurerm_resource_group.main.name
  sku_name    = var.mysql-svc["sku_name"]
  subnet_id   = azurerm_subnet.main["db"].id
  env         = var.env
}

module "redis-svc" {
  source      = "./modules/redis"
  name        = var.redis-svc["name"]
  rg_location = azurerm_resource_group.main.location
  rg_name     = azurerm_resource_group.main.name
  sku_name    = var.redis-svc["sku_name"]
  env         = var.env
}



#
# module "aks" {
#   source          = "./modules/aks"
#   env             = var.env
#   subnet_id       = azurerm_subnet.main["app"].id
#   default_rg_name = var.default_rg_name
#
#   rg_name     = azurerm_resource_group.main.name
#   rg_location = azurerm_resource_group.main.location
#
#   slack_url = "https://slack.com"
#
# }
#
#
