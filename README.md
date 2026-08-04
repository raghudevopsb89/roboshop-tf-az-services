# roboshop-tf-az-services

Terraform for the RoboShop stack on Azure: networking, the four managed
datastores, an AKS cluster + ACR, and the Kubernetes manifests that run the
eight application services on top.

## What gets created

| Component | Resource | Notes |
|-----------|----------|-------|
| Network | `azurerm_virtual_network` `dev` (`10.20.0.0/22`) | subnets `app` (nodes) and `db` (MySQL delegated), peered both ways with `workstation-vnet` |
| MySQL | Flexible Server `rbmysql-dev` | VNet-injected, public access off, reached via a private DNS zone; schemas `catalogue`, `cities`, `ratings` |
| MongoDB | Cosmos DB for MongoDB `rbmongodb-dev` | databases `users`, `orders` |
| Redis | Azure Managed Redis `rbredis-dev` | TLS (`Encrypted`) + access-key auth |
| Messaging | Service Bus `rbservicebus-dev` | queue `orders` (payment publishes, orders consumes) |
| Registry | ACR `roboshopb89dev` | AKS kubelet holds `AcrPull` |
| Compute | AKS `rbaks-dev` | Azure CNI Overlay, nodes in the `app` subnet |

### Why MySQL needs the private DNS zone

The server runs with `publicNetworkAccess = Disabled` and a delegated subnet, so
its FQDN (`rbmysql-dev.mysql.database.azure.com`) is a CNAME into a private zone.
Without an `azurerm_private_dns_zone` linked to the VNet that CNAME resolves to
**NXDOMAIN** and nothing can connect — `modules/mysql` creates and links it.

### Why the `app` subnet has no delegation

A subnet delegated to `Microsoft.ContainerService/managedClusters` is reserved
for API Server VNet Integration and is rejected as a node pool subnet, so `app`
is left undelegated.

### Why the Cosmos collections are declared in Terraform

Cosmos DB for MongoDB refuses any query that sorts on an unindexed field
(`The index path corresponding to the specified order-by item is excluded`).
Orders is read with `findByUserIdOrderByOrderDateDesc`, so `modules/mongodb`
declares the collections with indexes on `userId` and `orderDate` instead of
letting the app auto-create them on first write.

### Why `cities` is in the seed job

Shipping runs with `ddl-auto=validate` *and*
`defer-datasource-initialization=true`, so Hibernate validates the schema before
the app's own `schema.sql` runs — the table must already exist or the service
crash-loops. The seed job creates it; the app's idempotent `schema.sql`/`data.sql`
still populate the rows on boot.

## Known behaviour

- `orders` logs `Failed to send notification: ... http://notification:8008` on
  every order. There is no notification service in this stack; the call is
  wrapped in a try/catch and does not affect the order, which is still saved.
- New Relic agents log a missing-license-key error at startup in several
  services. Harmless — no `NEW_RELIC_LICENSE_KEY` is configured.

## Deploy

```bash
make dev          # terraform init + apply (infra)
make app          # kubeconfig + ingress controller + images + manifests + seed
```

`make app` is the composition of these, runnable individually:

| Target | Does |
|--------|------|
| `kubeconfig` | `az aks get-credentials` for the cluster |
| `ingress` | installs ingress-nginx via Helm |
| `images` | builds the 8 service images and pushes them to ACR |
| `deploy` | renders `k8s/*.yaml` against Terraform outputs and applies them |
| `seed` | loads the catalogue + ratings schemas and master data |

Application source is a separate repo; the image build reads it from
`APPS_DIR` (default `/home/devops/azure-services/apps`).

## Connection details

All wiring the apps need is exposed as Terraform outputs; secrets are marked
sensitive.

```bash
terraform output                 # hosts, ports, cluster + registry names
terraform output -json           # includes keys and connection strings
```

`k8s/deploy.sh` reads those outputs and materialises them as the
`roboshop-secrets` Secret, so no credentials are ever committed.

## Layout

```
main.tf, variables.tf, outputs.tf   root: network, peering, module wiring
provider.tf                         azurerm backend + provider
env-dev/main.tfvars                 dev inputs
env-dev/state.tfvars                remote state backend config
modules/{mysql,mongodb,redis,servicebus,acr,aks}/
k8s/                                manifests + deploy/build/seed scripts
```
