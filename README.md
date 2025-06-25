# ⚡ Small K8s on Hetzner

Provision a **1-node Kubernetes cluster** on Hetzner Cloud using Cluster API (CAPI) + CAPH. Useful for quick testing, dev and small projects. Inspired by `https://community.hetzner.com/tutorials/kubernetes-on-hetzner-with-cluster-api`

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
export CONTROL_PLANE_MACHINE_COUNT=1
export WORKER_MACHINE_COUNT=0
export KUBERNETES_VERSION=1.33.2
export HCLOUD_CONTROL_PLANE_MACHINE_TYPE="cax11"
export HCLOUD_WORKER_MACHINE_TYPE="cax11"
export CONTROL_PLANE_ENDPOINT_HOST=<EXTERNAL_IP_FROM_HCLOUD>
export CERT_EMAIL=<YOUR_EMAIL>
export CLUSTER_NAME=<CLUSTER_NAME>
```

---

## 🧰 Step 2: Create Local Management Cluster

```bash
kind create cluster --name caph-mgt-cluster
clusterctl init --core cluster-api --bootstrap kubeadm --control-plane kubeadm --infrastructure hetzner
```

---

## 🔐 Step 3: Add Hetzner Token Secret

```bash
kubectl create secret generic hetzner --from-literal=hcloud=$API_CLUSTER_HCLOUD_TOKEN
```

---

## 🚀 Step 4: Provision Cluster

```bash
envsubst '${CLUSTER_NAME} ${KUBERNETES_VERSION} ${HCLOUD_CONTROL_PLANE_MACHINE_TYPE} ${HCLOUD_WORKER_MACHINE_TYPE} ${CONTROL_PLANE_ENDPOINT_HOST} ${HCLOUD_REGION} ${SSH_KEY_NAME}'  < configs/make-cluster-hetzner-kubeconfig.yaml | kubectl apply -f -
clusterctl get kubeconfig $CLUSTER_NAME > cluster-api-kubeconfig.yaml
export KUBECONFIG=cluster-api-kubeconfig.yaml
```

### Check K8S status
```bash
kubectl get nodes -o wide
```

---

## ⚙️ Step 5: Basic Config & Bootstrap.

### Use Makefile
```bash
make all
```

### OR setup manually:

```bash
# Remove default taints from control plane nodes to allow workloads on the control plane.
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl taint nodes --all node.cloudprovider.kubernetes.io/uninitialized-
kubectl get nodes
```

```bash
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
kubectl rollout status -n metallb-system deployment/controller --timeout=5m
kubectl rollout status -n metallb-system daemonset/speaker --timeout=5m
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

## 🧪 Step 6: Verify. Traefik Dashboard
Get Traefik dashboard URL
Replace <IP> with your cluster's external IP
```http://<IP>/dashboard/```


---

## 🧹 Cleanup

```bash
# Delete workload cluster on Hetzner
export KUBECONFIG=~/.kube/config
envsubst < configs/make-cluster-hetzner-kubeconfig.yaml| kubectl delete -f -

# Delete local management cluster
kind delete cluster --name caph-mgt-cluster
```
