# ⚡ Small (all in one node) K8s cluster on Hetzner

Provision a **1-node Kubernetes cluster** on Hetzner Cloud using Cluster API (CAPI) + CAPH. Useful for quick testing, dev and small projects. Inspired by [kubernetes-on-hetzner-with-cluster-api](https://community.hetzner.com/tutorials/kubernetes-on-hetzner-with-cluster-api)

---

## ✅ Prerequisites

- Docker
- Kind
- `kubectl`, `clusterctl`
- Helm
- Hetzner API token
- SSH key in Hetzner project

---

## 🌐 Step 1: Define environment variables

```bash
export API_CLUSTER_HCLOUD_TOKEN=<YOUR_HCLOUD_TOKEN>
export SSH_KEY_NAME=<YOUR_SSH_KEY_NAME>
export HCLOUD_REGION="fsn1"
export KUBERNETES_VERSION=1.33.2
export HCLOUD_CONTROL_PLANE_MACHINE_TYPE="cax11"
export CONTROL_PLANE_ENDPOINT_HOST=<EXTERNAL_SERVER_IP_HCLOUD>
export CERT_EMAIL=<YOUR_EMAIL>
export CLUSTER_NAME=<CLUSTER_NAME>
```

> **Important:**
> `CONTROL_PLANE_ENDPOINT_HOST` must be set to the IP address used for the Kubernetes control plane.
> **You can use either:**
> - **A new, pre-allocated Hetzner floating IP**
> - **An existing IP address** already assigned to your Hetzner project


---

## 🧰 Step 2: Create Local Management Cluster

```bash
kind create cluster --name caph-mgt-cluster
clusterctl init --core cluster-api --bootstrap kubeadm --control-plane kubeadm --infrastructure hetzner
export KUBECONFIG=~/.kube/config

# Wait for nodes to be ready
kubectl wait --for=condition=ready node --all --timeout=300s

# Add Hetzner Token Secret
kubectl create secret generic hetzner --from-literal=hcloud=$API_CLUSTER_HCLOUD_TOKEN
```

## 🚀 Step 3: Create K8s on Hetzner
```bash
export KUBECONFIG=~/.kube/config

# Deploy a cluster on Hetzner
envsubst '${CLUSTER_NAME} ${KUBERNETES_VERSION} ${HCLOUD_CONTROL_PLANE_MACHINE_TYPE} ${CONTROL_PLANE_ENDPOINT_HOST} ${HCLOUD_REGION} ${SSH_KEY_NAME}'  < configs/make-cluster-hetzner-kubeconfig.yaml | kubectl apply -f -

# Wait for the control plane to be ready (KubeadmControlPlane)
scripts/cluster-status-checker.sh

#  Get kubeconfig
clusterctl get kubeconfig $CLUSTER_NAME > cluster-api-kubeconfig.yaml

```

---

## ⚙️ Step 4: Bootstrap K8s Cluster Components.

### Use Makefile
```bash
export KUBECONFIG=cluster-api-kubeconfig.yaml
make all
```

### OR setup components manually:

```bash
export KUBECONFIG=cluster-api-kubeconfig.yaml

# Remove default taints from control plane nodes to allow workloads on the control plane.
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl taint nodes --all node.cloudprovider.kubernetes.io/uninitialized-
kubectl get nodes

# Hetzner CCM
helm repo add hcloud https://charts.hetzner.cloud
helm repo update hcloud
helm upgrade --install hccm hcloud/hcloud-cloud-controller-manager \
        --namespace kube-system \
        --set env.HCLOUD_TOKEN.valueFrom.secretKeyRef.name=hetzner \
        --set env.HCLOUD_TOKEN.valueFrom.secretKeyRef.key=hcloud

# Flannel CNI
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
# Wait for MetalLB readiness
kubectl rollout status -n metallb-system deployment/controller --timeout=2m
kubectl rollout status -n metallb-system daemonset/speaker --timeout=2m
# Apply MetalLB configuration
envsubst < configs/metallb-config.yaml | kubectl apply -f -

# (Optional) Hetzner CSI
helm upgrade --install hcloud-csi hcloud/hcloud-csi -n kube-system -f configs/csi-values.yaml

# Ingress: Traefik
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik -n traefik --create-namespace -f configs/traefik-values.yaml

# TLS: Cert-Manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true
envsubst < configs/cluster-issuer.yaml | kubectl apply -f -
```

---

## 🧪 Step 6: Verify. Access Traefik Dashboard
```bash
export KUBECONFIG=cluster-api-kubeconfig.yaml
# Add ingressroute for Traefik Dashboard
kubectl apply -f configs/traefik-dashboard-ingressroute.yaml

# Get Traefik dashboard URL
TRAEFIK_IP=$(kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Dashboard URL: http://$TRAEFIK_IP/dashboard/"
```

> **Security Note**: This exposes the dashboard publicly. For production, add authentication.

---

## 🧹 Cleanup

### Delete workload cluster on Hetzner

```bash
export API_CLUSTER_HCLOUD_TOKEN=<YOUR_HCLOUD_TOKEN>
export SSH_KEY_NAME=<YOUR_SSH_KEY_NAME>
export HCLOUD_REGION="fsn1"
export KUBERNETES_VERSION=1.33.2
export HCLOUD_CONTROL_PLANE_MACHINE_TYPE="cax11"
export CONTROL_PLANE_ENDPOINT_HOST=<EXTERNAL_SERVER_IP_HCLOUD>
export CERT_EMAIL=<YOUR_EMAIL>
export CLUSTER_NAME=<CLUSTER_NAME>
```

```bash
export KUBECONFIG=~/.kube/config
envsubst < configs/make-cluster-hetzner-kubeconfig.yaml| kubectl delete -f -
```

### Delete local management cluster
```bash
kind delete cluster --name caph-mgt-cluster
```
