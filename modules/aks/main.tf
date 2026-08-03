resource "azurerm_kubernetes_cluster" "main" {
  name                = "roboshop-${var.env}"
  location            = var.rg_location
  resource_group_name = var.rg_name
  dns_prefix          = "roboshop-${var.env}"
  kubernetes_version  = "1.35.4"

  default_node_pool {
    name           = "default"
    node_count     = 1
    vm_size        = "Standard_D2s_v3"
    vnet_subnet_id = var.subnet_id
  }

  network_profile {
    network_policy = "azure"
    network_plugin = "azure"
  }

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [default_node_pool]
  }

  # service_mesh_profile {
  #   mode      = "Istio"
  #   revisions = ["asm-1-29"]
  # }

}


resource "azurerm_role_assignment" "registry" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = "/subscriptions/3f2e42e1-ca06-4a99-8c56-be8d8ba306db/resourceGroups/denmark-east-rg/providers/Microsoft.ContainerRegistry/registries/raghudevopsb89"
  skip_service_principal_aad_check = true
}

# Use this command to get the kubeconfig
# az aks get-credentials --resource-group denmark-east-rg --name roboshop-dev

resource "azurerm_kubernetes_cluster_node_pool" "pool1" {
  name                  = "pool1"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_D2s_v3"
  vnet_subnet_id        = var.subnet_id

  node_count           = 4
  auto_scaling_enabled = true
  min_count            = 4
  max_count            = 20

  lifecycle {
    ignore_changes = [upgrade_settings]
  }

}

