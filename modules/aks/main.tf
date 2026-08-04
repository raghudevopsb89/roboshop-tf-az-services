resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.name}-${var.env}"
  location            = var.rg_location
  resource_group_name = var.rg_name
  dns_prefix          = "${var.name}-${var.env}"

  default_node_pool {
    name           = "system"
    vm_size        = var.vm_size
    node_count     = var.node_count
    vnet_subnet_id = var.subnet_id

    # Azure applies these defaults server-side; declaring them keeps every plan
    # from showing the block as drift.
    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # Azure CNI Overlay: pods get IPs from pod_cidr instead of burning addresses
  # in the /24 node subnet, which only has ~250 usable IPs.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    load_balancer_sku   = "standard"
  }

  node_provisioning_profile {
    mode = "Manual"
  }
}

# Lets the kubelet pull the roboshop images without an imagePullSecret.
resource "azurerm_role_assignment" "acr_pull" {
  scope                            = var.acr_id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
