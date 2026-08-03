env           = "dev"
location      = "Denmark East"
address_space = ["10.20.0.0/22"]
subnets = {
  app = {
    cidr = "10.20.0.0/24"
    subnet_delegations = [
      {
        name                       = "aks-delegation"
        service_delegation_name    = "Microsoft.ContainerService/managedClusters"
        service_delegation_actions = []
      }
    ]
  }
  db = {
    cidr = "10.20.1.0/24"
    subnet_delegations = [
      {
        name                       = "mysql-delegation"
        service_delegation_name    = "Microsoft.DBforMySQL/flexibleServers"
        service_delegation_actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    ]
  }
}

vms = {
  mysql = {
    vm_size = "Standard_B1ms"
  }
  valkey = {}
  mongodb = {
    vm_size = "Standard_B1ms"
  }
  rabbitmq = {}
}

image_id        = "/subscriptions/3f2e42e1-ca06-4a99-8c56-be8d8ba306db/resourceGroups/denmark-east-rg/providers/Microsoft.Compute/galleries/rhel10/images/1.0.0/versions/1.0.0"
default_rg_name = "denmark-east-rg"

mysql-svc = {
  name     = "rbmysql"
  sku_name = "B_Standard_B1ms"
}

redis-svc = {
  name     = "rbredis"
  sku_name = "Balanced_B1"
}

