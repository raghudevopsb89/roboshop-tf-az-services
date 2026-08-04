env           = "dev"
location      = "Denmark East"
address_space = ["10.20.0.0/22"]
subnets = {
  # AKS node subnet. Deliberately NOT delegated: a subnet delegated to
  # Microsoft.ContainerService/managedClusters is reserved for API Server VNet
  # Integration and cannot be used as a node pool subnet.
  app = {
    cidr               = "10.20.0.0/24"
    subnet_delegations = []
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

default_rg_name = "denmark-east-rg"

mysql-svc = {
  name     = "rbmysql"
  sku_name = "B_Standard_B1ms"
  # Databases the roboshop services expect.
  databases = ["catalogue", "cities", "ratings"]
}

redis-svc = {
  name     = "rbredis"
  sku_name = "Balanced_B1"
}

mongodb-svc = {
  name = "rbmongodb"
  # user service -> users, orders service -> orders
  databases = ["users", "orders"]
  collections = {
    users = {
      name     = "users"
      database = "users"
      indexes = [
        { keys = ["_id"], unique = true },
        { keys = ["username"], unique = false },
        { keys = ["email"], unique = false },
      ]
    }
    # orders is queried with findByUserIdOrderByOrderDateDesc, so both the
    # filter field and the sort field need an index.
    orders = {
      name     = "orders"
      database = "orders"
      indexes = [
        { keys = ["_id"], unique = true },
        { keys = ["userId"], unique = false },
        { keys = ["orderDate"], unique = false },
      ]
    }
  }
}

servicebus-svc = {
  name = "rbservicebus"
  sku  = "Standard"
  # payment publishes, orders consumes
  queues = ["orders"]
}

aks-svc = {
  name       = "rbaks"
  vm_size    = "Standard_B2s_v2"
  node_count = 2
  # Overlay keeps pod IPs off the /24 node subnet.
  pod_cidr       = "10.244.0.0/16"
  service_cidr   = "10.30.0.0/16"
  dns_service_ip = "10.30.0.10"
}

acr-svc = {
  name = "roboshopb89"
  sku  = "Basic"
}

