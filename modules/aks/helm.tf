resource "null_resource" "kube-config" {

  depends_on = [azurerm_kubernetes_cluster_node_pool.pool1]

  provisioner "local-exec" {
    command = "az aks get-credentials --resource-group ${var.rg_name} --name roboshop-${var.env} --overwrite-existing"
  }
}

resource "helm_release" "traefik_ingress" {

  depends_on = [null_resource.kube-config, helm_release.prometheus_stack]

  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"

  values = [
    yamlencode({
      additionalArguments = [
        "--accesslog=true",
        "--accesslog.format=json"
      ]
      metrics = {
        prometheus = {
          enabled              = true
          entryPoint           = "metrics"
          addEntryPointsLabels = true
          addRoutersLabels     = true
          addServicesLabels    = true

          # 1. Enable a clean, dedicated service for metrics scraping
          service = {
            enabled = true
          }

          # 2. Match your Prometheus Operator label selector exactly
          serviceMonitor = {
            enabled = true
            additionalLabels = {
              release = "pstack" # <-- CHANGED TO MATCH YOUR CLUSTER
            }
            interval    = "30s"
            honorLabels = true
          }
        }
      }
      ports = {
        metrics = {
          port = 9100
          expose = {
            default = true
          }
          exposedPort = 9100
        }
      }
    })
  ]

}

resource "helm_release" "prometheus_stack" {

  depends_on = [null_resource.kube-config]

  name       = "pstack"
  repository = "oci://ghcr.io/prometheus-community/charts"
  chart      = "kube-prometheus-stack"

  values = [
    yamlencode({

      kubeProxy = {
        enabled = true
      }

      grafana = {
        ingress = {
          enabled          = true
          ingressClassName = "traefik"
          hosts            = ["grafana-${var.env}.rdevopsb89.online"]
          path             = "/"
          pathType         = "Prefix"
        }
      }

      alertmanager = {
        enabled = true
        ingress = {
          enabled          = true
          ingressClassName = "traefik"
          hosts            = ["alertmanager-${var.env}.rdevopsb89.online"]
          paths            = ["/"]
          pathType         = "Prefix"
        }

        # This block directly replaces the default configuration you see in the pod
        config = {
          global = {
            resolve_timeout = "5m"
          }
          route = {
            receiver        = "slack-notifications" # Overwrites "null"
            group_by        = ["namespace", "alertname"]
            group_wait      = "30s"
            group_interval  = "5m"
            repeat_interval = "12h"

            # Keeps the Watchdog alert muted or routes it normally
            routes = [
              {
                receiver = "null"
                matchers = ["alertname=\"Watchdog\""]
              }
            ]
          }
          receivers = [
            {
              name = "null" # Keeps the default null receiver intact
            },
            {
              name = "slack-notifications"
              slack_configs = [
                {
                  api_url       = var.slack_url
                  channel       = "#all-raghudevopsb89"
                  send_resolved = true
                  text          = "Alert: {{ .CommonAnnotations.summary }}\nDescription: {{ .CommonAnnotations.description }}"
                }
              ]
            }
          ]
        }
      }

      prometheus = {
        ingress = {
          enabled          = true
          ingressClassName = "traefik"
          hosts            = ["prometheus-${var.env}.rdevopsb89.online"]
          paths            = ["/"]
          pathType         = "Prefix"
        }
        prometheusSpec = {
          additionalScrapeConfigs = [
            {
              job_name = "azure-vms"
              azure_sd_configs = [
                {
                  subscription_id = "3f2e42e1-ca06-4a99-8c56-be8d8ba306db"
                  tenant_id       = "229f3fa3-57f3-4e2c-852f-24b7bf512640"
                  client_id       = data.azurerm_key_vault_secret.PrometheusClientID.value
                  client_secret   = data.azurerm_key_vault_secret.PrometheusClientPassword.value
                  port            = 9100
                  resource_group  = var.rg_name
                }
              ]
              relabel_configs = [
                {
                  source_labels = ["__meta_azure_machine_name"]
                  target_label  = "instance_name"
                },
                {
                  source_labels = ["__meta_azure_machine_resource_group"]
                  target_label  = "resource_group"
                },
                {
                  source_labels = ["__meta_azure_machine_location"]
                  target_label  = "region"
                }
              ]
            }
          ]
        }
      }
    })
  ]
}

## External DNS Helm chart secret
resource "null_resource" "external-dns-secret" {
  depends_on = [
    null_resource.kube-config
  ]

  provisioner "local-exec" {
    command = <<EOF
echo '{
  "tenantId": "229f3fa3-57f3-4e2c-852f-24b7bf512640",
  "subscriptionId": "3f2e42e1-ca06-4a99-8c56-be8d8ba306db",
  "resourceGroup": "${var.default_rg_name}",
  "aadClientId": "${data.azurerm_key_vault_secret.ClientID.value}",
  "aadClientSecret": "${data.azurerm_key_vault_secret.ClientPassword.value}"
}' >/tmp/azure.json
kubectl create secret generic azure-config-file --from-file /tmp/azure.json
EOF
  }

}

resource "helm_release" "external_dns" {

  depends_on = [null_resource.external-dns-secret]

  chart      = "external-dns"
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"

  values = [
    file("${path.module}/helm-values/external-dns.yml")
  ]

}

resource "local_file" "prom-input" {
  filename = "/tmp/prom.yml"
  content = yamlencode({
    grafana = {
      ingress = {
        enabled          = true
        ingressClassName = "traefik"
        hosts            = ["grafana-${var.env}.rdevopsb89.online"]
        path             = "/"
        pathType         = "Prefix"
      }
    }
    prometheus = {
      ingress = {
        enabled          = true
        ingressClassName = "traefik"
        hosts            = ["prometheus-${var.env}.rdevopsb89.online"]
        paths            = ["/"]
        pathType         = "Prefix"
      }
      prometheusSpec = {
        additionalScrapeConfigs = [
          {
            job_name = "azure-vms"
            azure_sd_configs = [
              {
                subscription_id = "3f2e42e1-ca06-4a99-8c56-be8d8ba306db"
                tenant_id       = "229f3fa3-57f3-4e2c-852f-24b7bf512640"
                client_id       = data.azurerm_key_vault_secret.PrometheusClientID.value
                client_secret   = data.azurerm_key_vault_secret.PrometheusClientPassword.value
                port            = 9100
                resource_group  = var.rg_name
              }
            ]
            relabel_configs = [
              {
                source_labels = ["__meta_azure_machine_name"]
                target_label  = "instance_name"
              },
              {
                source_labels = ["__meta_azure_machine_resource_group"]
                target_label  = "resource_group"
              },
              {
                source_labels = ["__meta_azure_machine_location"]
                target_label  = "region"
              }
            ]
          }
        ]
      }
    }
  })
}

# ELK Server , we kept off, hence commented
# resource "helm_release" "file-beat" {
#
#   depends_on = [null_resource.kube-config]
#
#   name       = "filebeat"
#   repository = "https://helm.elastic.co"
#   chart      = "filebeat"
#
#   values = [
#     file("${path.module}/helm-values/filebeat.yml")
#   ]
# }

## External Secrets Helm chart secret
resource "null_resource" "external-secret" {
  depends_on = [
    null_resource.kube-config
  ]

  provisioner "local-exec" {
    command = <<EOF
kubectl create ns roboshop
kubectl label namespace roboshop istio-injection=enabled
kubectl create secret generic azure-secret-sp --from-literal=ClientID=984e8346-9453-44a8-8fe6-054fbbd174ce   --from-literal=ClientSecret='${data.azurerm_key_vault_secret.ExternalSecretClientPassword.value}' -n roboshop
EOF
  }

}

resource "helm_release" "external_secrets" {

  depends_on = [null_resource.external-secret]

  chart      = "external-secrets"
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"

  values = [
    file("${path.module}/helm-values/external-secrets.yml")
  ]
}


resource "helm_release" "cert-manager" {

  depends_on = [null_resource.external-secret]

  chart      = "cert-manager"
  name       = "cert-manager"
  repository = "oci://quay.io/jetstack/charts"

  set = [
    {
      name  = "crds.enabled"
      value = "true"
    }
  ]
}

## Issuer for cert-manager
resource "null_resource" "cluster-issuer" {
  depends_on = [
    null_resource.kube-config,
    helm_release.cert-manager
  ]

  provisioner "local-exec" {
    command = <<EOF
kubectl apply -f ${path.module}/helm-values/cm-issuer.yml
EOF
  }
}

## ISTIO
resource "helm_release" "istio-base" {
  depends_on = [
    null_resource.kube-config
  ]

  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = true
}


resource "helm_release" "istiod" {
  depends_on = [
    null_resource.kube-config,
    helm_release.istio-base
  ]

  name             = "istiod"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "istiod"
  namespace        = "istio-system"
  create_namespace = true
}

resource "null_resource" "kiali" {
  depends_on = [
    null_resource.kube-config,
    helm_release.istiod
  ]
  provisioner "local-exec" {
    command = <<EOF
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/addons/kiali.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/addons/grafana.yaml
kubectl apply -f - <<EOK
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kiali
  namespace: istio-system
spec:
  ingressClassName: traefik
  rules:
  - host: kiali-dev.rdevopsb89.online
    http:
      paths:
      - backend:
          service:
            name: kiali
            port:
              number: 20001
        path: /kiali
        pathType: Prefix
EOK
EOF
  }
}



resource "helm_release" "argocd" {

  depends_on = [null_resource.kube-config, helm_release.traefik_ingress]

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"

  set = [
    {
      name  = "server.ingress.enabled"
      value = true
    },
    {
      name  = "server.ingress.ingressClassName"
      value = "traefik"
    },
    {
      name  = "global.domain"
      value = "argocd-${var.env}.rdevopsb89.online"
    },
    {
      name  = "configs.params.server\\.insecure"
      value = true
    }
  ]
}


