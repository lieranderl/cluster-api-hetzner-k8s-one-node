KUBECONFIG ?= cluster-api-kubeconfig.yaml
METALLB_CONFIG ?= configs/metallb-config.yaml
TRAEFIK_VALUES ?= configs/traefik-values.yaml
CLUSTER_ISSUER ?= configs/cluster-issuer.yaml

export KUBECONFIG

.PHONY: all cluster-setup cni metallb ccm csi traefik cert-manager issuer

all: cluster-setup cni metallb ccm csi traefik cert-manager issuer

cluster-setup:
	kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
	kubectl taint nodes --all node.cloudprovider.kubernetes.io/uninitialized- || true
	kubectl get nodes

cni:
	kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

metallb:
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
	envsubst < $(METALLB_CONFIG) | kubectl apply -f -

ccm:
	helm repo add syself https://charts.syself.com/ || true
	helm repo update syself
	helm upgrade --install ccm syself/ccm-hetzner -n kube-system || true

csi:
	helm repo add hcloud https://charts.hetzner.cloud || true
	helm repo update hcloud
	helm upgrade --install hcloud-csi hcloud/hcloud-csi -n kube-system || true

traefik:
	helm repo add traefik https://traefik.github.io/charts || true
	helm repo update
	helm upgrade --install traefik traefik/traefik -n traefik --create-namespace -f $(TRAEFIK_VALUES)

cert-manager:
	helm repo add jetstack https://charts.jetstack.io || true
	helm repo update
	helm upgrade --install cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--create-namespace \
		--set crds.enabled=true

issuer:
	envsubst < $(CLUSTER_ISSUER) | kubectl apply -f -
