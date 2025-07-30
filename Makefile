WORKLOAD_KUBECONFIG ?= workload-kubeconfig.yaml
MANAGEMENT_KUBECONFIG ?= management-kubeconfig.yaml
MAKE_CONFIG ?= configs/make-cluster-hetzner-kubeconfig.yaml
METALLB_CONFIG ?= configs/metallb-config.yaml
TRAEFIK_VALUES ?= configs/traefik-values.yaml
CLUSTER_ISSUER ?= configs/cluster-issuer.yaml
CSI_VALUES ?= configs/csi-values.yaml
GATEWAY_API_VERSION = v1.2.0
CILIUM_POOL?= configs/cilium-lbpool.yaml
CILIUM_ANNOUNCEMENT?= configs/cilium-l2announcement-policy.yaml
CILIUM_HUBBLE_EXPOSE_TEST?= configs/cilium-hubble-expose-test.yaml


ifneq ("$(wildcard .env)","")
	include .env
	export
endif


.ONESHELL:
SHELL := /bin/bash
MAKEFLAGS += --no-builtin-rules


.PHONY: all workload-bootstrap management-cluster remove-taints  workload-cluster cni ccm metallb csi traefik cert-manager issuer delete-workload-cluster delete-management-cluster verify-env helm-init help

# Default target
# If no target is specified, show a message
# and exit with an error code
# This prevents running the Makefile without a target
# and provides a clear message to the user
.DEFAULT_GOAL := no_default
no_default:
	@echo "Please specify a target (e.g., make management-cluster)."
	@exit 1

# all: management-cluster workload-cluster remove-taints  ccm cni metallb csi traefik cert-manager issuer ## Create full cluster (management + workload + all addons)
workload-bootstrap: remove-taints ccm cni metallb csi traefik cert-manager issuer  ## Install core components, metallb, traefik, cert-manager, issuer into workload cluster
workload-cilium: remove-taints ccm gateway-crds cilium csi cilium-pool ## Install Cilium and core components into workload cluster
hubble-test-start: cilium-hubble-on cilium-hubble-expose-start-test ## Start Hubble test
hubble-test-stop: cilium-hubble-expose-stop-test ## Stop Hubble test

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
	envsubst '$${CLUSTER_NAME} $${KUBERNETES_VERSION} $${CONTAINERD} $${RUNC} $${HCLOUD_CONTROL_PLANE_MACHINE_TYPE} $${CONTROL_PLANE_ENDPOINT_HOST} $${HCLOUD_REGION} $${SSH_KEY_NAME}'  < ${MAKE_CONFIG}  | kubectl apply -f -
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

gateway-crds: ## Install Gateway API CRDs
	KUBECONFIG=${WORKLOAD_KUBECONFIG} kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
	KUBECONFIG=${WORKLOAD_KUBECONFIG} kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
	KUBECONFIG=${WORKLOAD_KUBECONFIG} kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
	KUBECONFIG=${WORKLOAD_KUBECONFIG} kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
	KUBECONFIG=${WORKLOAD_KUBECONFIG} kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml


cilium: helm-init ## Remove kube-proxy and install Cilium with Gateway API support
	@echo "Removing kube-proxy..."
	KUBECONFIG=${WORKLOAD_KUBECONFIG} kubectl -n kube-system delete ds kube-proxy
	KUBECONFIG=${WORKLOAD_KUBECONFIG} kubectl -n kube-system delete cm kube-proxy
	@echo "🌐 Installing Cilium (with kube-proxy replacement and Gateway API) using cilium CLI"
	KUBECONFIG=${WORKLOAD_KUBECONFIG} cilium install \
		--set kubeProxyReplacement=true \
		--set gatewayAPI.enabled=true \
		--set l2Announcements.enabled=true

	@echo "⏳ Waiting for Cilium to be ready..."
	KUBECONFIG=${WORKLOAD_KUBECONFIG} cilium status --wait


cilium-pool: ## Create Cilium IP Pool and announce it to the cluster
	envsubst < ${CILIUM_POOL} | KUBECONFIG=${WORKLOAD_KUBECONFIG} kubectl apply -f -
	envsubst < ${CILIUM_ANNOUNCEMENT} | KUBECONFIG=${WORKLOAD_KUBECONFIG} kubectl apply -f -

cilium-hubble-on: ## Enable Cilium Hubble and wait for it to be ready
		KUBECONFIG=${WORKLOAD_KUBECONFIG} cilium hubble enable --ui
		KUBECONFIG=${WORKLOAD_KUBECONFIG} cilium status --wait

cilium-hubble-off: ## Disable Cilium Hubble and wait for it to be ready
		KUBECONFIG=${WORKLOAD_KUBECONFIG} cilium hubble disable
		KUBECONFIG=${WORKLOAD_KUBECONFIG} cilium status --wait

cilium-hubble-expose-start-test:
		KUBECONFIG=${WORKLOAD_KUBECONFIG} kubectl apply -f ${CILIUM_HUBBLE_EXPOSE_TEST}
		@echo "✅ Cilium Hubble exposed"
		@echo "Getting exposed URL..."
		@echo
		KUBECONFIG=${WORKLOAD_KUBECONFIG} kubectl get svc cilium-gateway-test-gateway -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' | xargs -I {} echo "http://{}:8080/?namespace=kube-system"

cilium-hubble-expose-stop-test:
		KUBECONFIG=${WORKLOAD_KUBECONFIG} kubectl delete -f ${CILIUM_HUBBLE_EXPOSE_TEST}

cilium-status: ## Wait for Cilium to be ready
	KUBECONFIG=${WORKLOAD_KUBECONFIG} cilium status --wait

helm-init: ## Add Helm repos for required components
	@echo "📦 Initializing Helm repos..."
	helm repo add traefik https://traefik.github.io/charts || true
	helm repo add hcloud https://charts.hetzner.cloud || true
	helm repo add jetstack https://charts.jetstack.io || true
	helm repo add cilium https://helm.cilium.io/ || true
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
	envsubst '$${CLUSTER_NAME} $${KUBERNETES_VERSION} $${CONTAINERD} $${RUNC} $${HCLOUD_CONTROL_PLANE_MACHINE_TYPE} $${CONTROL_PLANE_ENDPOINT_HOST} $${HCLOUD_REGION} $${SSH_KEY_NAME}'  < ${MAKE_CONFIG} | KUBECONFIG=${MANAGEMENT_KUBECONFIG} kubectl delete -f -
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
