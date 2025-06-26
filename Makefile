WORKLOAD_KUBECONFIG ?= workload-kubeconfig.yaml
MANAGEMENT_KUBECONFIG ?= management-kubeconfig.yaml
MAKE_CONFIG ?= configs/make-cluster-hetzner-kubeconfig.yaml
METALLB_CONFIG ?= configs/metallb-config.yaml
TRAEFIK_VALUES ?= configs/traefik-values.yaml
CLUSTER_ISSUER ?= configs/cluster-issuer.yaml
CSI_VALUES ?= configs/csi-values.yaml

ifneq ("$(wildcard .env)","")
	include .env
	export
endif


.ONESHELL:
SHELL := /bin/bash
MAKEFLAGS += --no-builtin-rules

.PHONY: all workload-bootstrap management-cluster remove-taints  workload-cluster cni ccm metallb csi traefik cert-manager issuer delete-workload-cluster delete-management-cluster verify-env helm-init help

all: management-cluster workload-cluster remove-taints  ccm cni metallb csi traefik cert-manager issuer ## Create full cluster (management + workload + all addons)
workload-bootstrap: remove-taints ccm cni metallb csi traefik cert-manager issuer  ## Install core components into workload cluster

management-cluster: verify-env ## Create Kind-based management cluster
	@echo "🧰 Creating local management cluster..."
	kind create cluster --name caph-mgt-cluster
	kind get kubeconfig  --name  caph-mgt-cluster > ${MANAGEMENT_KUBECONFIG}
	clusterctl init --core cluster-api --bootstrap kubeadm --control-plane kubeadm --infrastructure hetzner
	@echo "🔒 Adding Hetzner token secret..."
	export KUBECONFIG=${MANAGEMENT_KUBECONFIG}
	kubectl create secret generic hetzner --from-literal=hcloud=${API_CLUSTER_HCLOUD_TOKEN}
	@echo "⏳ Waiting for nodes to be ready..."
	kubectl wait --for=condition=ready node --all --timeout=300s

workload-cluster: verify-env ## Provision workload cluster on Hetzner
	export KUBECONFIG=${MANAGEMENT_KUBECONFIG}
	@echo "🚀 Creating workload cluster on Hetzner..."
	envsubst '$${CLUSTER_NAME} $${KUBERNETES_VERSION} $${HCLOUD_CONTROL_PLANE_MACHINE_TYPE} $${CONTROL_PLANE_ENDPOINT_HOST} $${HCLOUD_REGION} $${SSH_KEY_NAME}'  < ${MAKE_CONFIG}  | kubectl apply -f -
	./scripts/cluster-status-checker.sh
	clusterctl get kubeconfig ${CLUSTER_NAME} > ${WORKLOAD_KUBECONFIG}
	@echo "✅ Workload cluster created! Kubeconfig saved to ${WORKLOAD_KUBECONFIG}"

remove-taints: ## Remove taints from workload control-plane nodes
	@echo "⚙️ Removing taints ..."
	export KUBECONFIG=${WORKLOAD_KUBECONFIG}
	kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
	kubectl taint nodes --all node.cloudprovider.kubernetes.io/uninitialized- || true
	kubectl get nodes

cni: ## Install Flannel CNI
	@echo "🌐 Installing Flannel CNI..."
	KUBECONFIG=${WORKLOAD_KUBECONFIG} kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

helm-init: ## Add Helm repos for required components
	@echo "📦 Initializing Helm repos..."
	helm repo add traefik https://traefik.github.io/charts || true
	helm repo add hcloud https://charts.hetzner.cloud || true
	helm repo add jetstack https://charts.jetstack.io || true
	helm repo update

ccm: helm-init ## Install Hetzner Cloud Controller Manager
	@echo "☁️ Installing Hetzner Cloud Controller Manager..."
	export KUBECONFIG=${WORKLOAD_KUBECONFIG}
	helm upgrade --install hccm hcloud/hcloud-cloud-controller-manager \
		--namespace kube-system \
		--set env.HCLOUD_TOKEN.valueFrom.secretKeyRef.name=hetzner \
		--set env.HCLOUD_TOKEN.valueFrom.secretKeyRef.key=hcloud

metallb: ## Install and configure MetalLB
	@echo "📶 Installing MetalLB..."
	export KUBECONFIG=${WORKLOAD_KUBECONFIG}
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
	kubectl rollout status -n metallb-system deployment/controller --timeout=2m
	kubectl rollout status -n metallb-system daemonset/speaker --timeout=2m
	envsubst < ${METALLB_CONFIG} | kubectl apply -f -

csi: helm-init ## Install Hetzner CSI driver
	@echo "💾 Installing Hetzner CSI..."
	export KUBECONFIG=${WORKLOAD_KUBECONFIG}
	helm upgrade --install hcloud-csi hcloud/hcloud-csi -n kube-system -f ${CSI_VALUES}

traefik: helm-init ## Install Traefik ingress controller
	@echo "🔀 Installing Traefik Ingress..."
	export KUBECONFIG=${WORKLOAD_KUBECONFIG}
	helm upgrade --install traefik traefik/traefik -n traefik --create-namespace -f ${TRAEFIK_VALUES}

cert-manager: helm-init ## Install Cert-Manager
	@echo "🔐 Installing Cert-Manager..."
	export KUBECONFIG=${WORKLOAD_KUBECONFIG}
	helm upgrade --install cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--create-namespace \
		--set crds.enabled=true

issuer: ## Apply ClusterIssuer for Cert-Manager
	@echo "🏷️ Creating Cluster Issuer..."
	envsubst < ${CLUSTER_ISSUER} | KUBECONFIG=${WORKLOAD_KUBECONFIG} kubectl apply -f -

delete-workload-cluster: verify-env ## Tear down workload cluster
	@echo "🗑️ Deleting workload cluster on Hetzner..."
	envsubst '$${CLUSTER_NAME} $${KUBERNETES_VERSION} $${HCLOUD_CONTROL_PLANE_MACHINE_TYPE} $${CONTROL_PLANE_ENDPOINT_HOST} $${HCLOUD_REGION} $${SSH_KEY_NAME}'  < ${MAKE_CONFIG} | KUBECONFIG=${MANAGEMENT_KUBECONFIG} kubectl delete -f -
	@echo "✅ Workload cluster deleted."

delete-management-cluster: ## Tear down management cluster
	@echo "🧹 Deleting local management cluster..."
	@if kind get clusters | grep -q caph-mgt-cluster; then \
		kind delete cluster --name caph-mgt-cluster; \
		echo "✅ Management cluster deleted."; \
	else \
		echo "⚠️ Management cluster not found, skipping."; \
	fi

verify-env: ## Verify required environment variables
	@required_vars="API_CLUSTER_HCLOUD_TOKEN SSH_KEY_NAME HCLOUD_REGION KUBERNETES_VERSION HCLOUD_CONTROL_PLANE_MACHINE_TYPE CONTROL_PLANE_ENDPOINT_HOST CERT_EMAIL CLUSTER_NAME"; \
	missing_vars=""; \
	for var in $$required_vars; do \
		if [ -z "$${!var}" ]; then \
			echo "Error: Environment variable $$var is not set."; \
			missing_vars="$$missing_vars $$var"; \
		fi; \
	done; \
	if [ -n "$$missing_vars" ]; then \
		exit 1; \
	else \
		echo "✅ All required environment variables are set."; \
	fi

help: ## Show help
	@echo "Available targets:"
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'
