common:
	git pull
	rm -f .terraform/terraform.tfstate

dev dev-apply: common
	terraform init -backend-config=env-dev/state.tfvars
	terraform apply -auto-approve -var-file=env-dev/main.tfvars


dev-destroy: common
	terraform init -backend-config=env-dev/state.tfvars
	terraform destroy -auto-approve -var-file=env-dev/main.tfvars

prod prod-apply: common
	terraform init -backend-config=env-prod/state.tfvars
	terraform apply -auto-approve -var-file=env-prod/main.tfvars


prod-destroy: common
	terraform init -backend-config=env-prod/state.tfvars
	terraform destroy -auto-approve -var-file=env-prod/main.tfvars


# ---- application layer (runs on the AKS cluster provisioned above) ----------

RG  = $(shell terraform output -raw aks_resource_group 2>/dev/null)
AKS = $(shell terraform output -raw aks_cluster_name 2>/dev/null)

kubeconfig:
	az aks get-credentials -g $(RG) -n $(AKS) --overwrite-existing

ingress:
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo update
	helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
		--namespace ingress-nginx --create-namespace \
		--wait --timeout 10m

images:
	./k8s/build-images.sh

deploy:
	./k8s/deploy.sh

seed:
	./k8s/seed-db.sh

# Full app bring-up on an already-applied stack.
app: kubeconfig ingress images deploy seed

.PHONY: common kubeconfig ingress images deploy seed app




