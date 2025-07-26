# ⚡ Small (All-in-One Node) Kubernetes cluster on Hetzner

Provision a **1-node Kubernetes cluster** on Hetzner Cloud using Cluster API (CAPI) + Syself CAPH. Ideal for quick testing, development, and small projects. Inspired by [kubernetes-on-hetzner-with-cluster-api](https://community.hetzner.com/tutorials/kubernetes-on-hetzner-with-cluster-api) and [Syself CAPH](https://syself.com/docs/caph/getting-started/introduction)

> 🛠️ This project uses a **Makefile** for automation. Run `make help` to see available commands.
> For more details, inspect the Makefile directly.

---

## ✅ Prerequisites

- Docker or containerd
- [Install `kind`](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [Install `kubectl`](https://kubernetes.io/docs/tasks/tools/#kubectl)
- [Install `clusterctl`](https://cluster-api.sigs.k8s.io/user/quick-start#install-clusterctl)
- [Install `helm`](https://helm.sh/docs/intro/install/)
- Hetzner API token
- SSH key in Hetzner project
- `cilium` as Cilium CLI, in case you want to use cilium. [Install the Cilium CLI](https://docs.cilium.io/en/latest/gettingstarted/k8s-install-default/#install-the-cilium-cli)

---

## 🌐 Step 1: Configure Environment

Create a .env file (see .env-example) and define all required variables.

> **Important:**
> `CONTROL_PLANE_ENDPOINT_HOST` must be set to the IP address used for the Kubernetes control plane.
> **You can use either:**
>
> - **A new, pre-allocated Hetzner floating IP**
> - **An existing IP address** already assigned to your Hetzner project

## 🧰 Step 2: Create Local Management Cluster

```bash
make management-cluster
```

## 🚀 Step 3: Create and Bootstrap K8s on Hetzner

- ### Create Cluster

```bash
make workload-cluster
```

- ### Add and use metallb, flannel CNI, Traefik in Cluster:

```bash
make workload-bootstrap
```

- ### **OR**: Add and use [Cilium](https://cilium.io/) with kube-proxy replacement, L2Announcement, CiliumLoadBalancerIPPool and Gateway API:

```bash
make workload-cilium
```

## 🧪 Step 4 (Optional): TEST

### Verify by accessing Traefik Dashboard (in case you picked `workload-bootstrap` on previous step):

```bash
export KUBECONFIG=workload-kubeconfig.yaml  # Default kubeconfig name generated for the workload cluster
# Add ingressroute for Traefik Dashboard
kubectl apply -f configs/traefik-dashboard-ingressroute.yaml

# Get Traefik dashboard URL
TRAEFIK_IP=$(kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Dashboard URL: http://$TRAEFIK_IP/dashboard/"
```

### **OR** Verify by accessing Hubble UI (in case you picked `workload-cilium` on previous step):

- Start

```bash
make hubble-test-start
```

- Stop

```bash
make hubble-test-stop
```

> **Security Note**: This exposes the dashboard publicly. For production, add authentication.

## 🧹 Cleanup

**Delete workload cluster on Hetzner**

```bash
make delete-workload-cluster
```

**Delete local management cluster**

```bash
make delete-management-cluster
```
