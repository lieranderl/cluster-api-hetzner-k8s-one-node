# ⚡ Small (All-in-One Node) Kubernetes cluster on Hetzner

Provision a **1-node Kubernetes cluster** on Hetzner Cloud using Cluster API (CAPI) + Syself CAPH. Ideal for quick testing, development, and small projects. Inspired by [kubernetes-on-hetzner-with-cluster-api](https://community.hetzner.com/tutorials/kubernetes-on-hetzner-with-cluster-api) and [Syself CAPH](https://syself.com/docs/caph/getting-started/introduction)

> 🛠️ This project uses a **Makefile** for automation. Run `make help` to see available commands.
> For more details, inspect the Makefile directly.

---

## ✅ Prerequisites

- Docker
- Kind
- `kubectl`, `clusterctl`
- Helm
- Hetzner API token
- SSH key in Hetzner project

---

## 🌐 Step 1: Define environment variables in .env file
Create a .env file (see .env-example) and define all required variables.

> **Important:**
> `CONTROL_PLANE_ENDPOINT_HOST` must be set to the IP address used for the Kubernetes control plane.
> **You can use either:**
> - **A new, pre-allocated Hetzner floating IP**
> - **An existing IP address** already assigned to your Hetzner project


## 🧰 Step 2: Create Local Management Cluster

```bash
make management-cluster
```

## 🚀 Step 3: Create and Bootstrap K8s on Hetzner
```bash
make workload-cluster
make workload-bootstrap
```

## 🧪 Step 4 (Optional): Verify by accessing Traefik Dashboard
```bash
export KUBECONFIG=workload-kubeconfig.yaml #default name for workload kubeconfig
# Add ingressroute for Traefik Dashboard
kubectl apply -f configs/traefik-dashboard-ingressroute.yaml

# Get Traefik dashboard URL
TRAEFIK_IP=$(kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Dashboard URL: http://$TRAEFIK_IP/dashboard/"
```

> **Security Note**: This exposes the dashboard publicly. For production, add authentication.



## 🧹 Cleanup

Delete workload cluster on Hetzner
```bash
make delete-workload-cluster
```

Delete local management cluster
```bash
make delete-management-cluster
```
