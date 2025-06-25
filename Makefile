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
	kubectl rollout status -n metallb-system deployment/controller --timeout=5m
	kubectl rollout status -n metallb-system daemonset/speaker --timeout=5m
	envsubst < $(METALLB_CONFIG) | kubectl apply -f -

ccm:
	helm repo add hcloud https://charts.hetzner.cloud || true
	helm repo update hcloud
	helm upgrade --install hccm hcloud/hcloud-cloud-controller-manager \
            --namespace kube-system \
            --set env.HCLOUD_TOKEN.valueFrom.secretKeyRef.name=hetzner \
            --set env.HCLOUD_TOKEN.valueFrom.secretKeyRef.key=hcloud || true

csi:
	helm upgrade --install hcloud-csi hcloud/hcloud-csi -n kube-system -f configs/csi-values.yaml || true

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
