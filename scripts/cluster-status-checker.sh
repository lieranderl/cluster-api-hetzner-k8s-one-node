#!/bin/bash

echo "🔍 Checking Cluster API resource readiness for cluster: $CLUSTER_NAME"

while true; do
  echo "⏳ Running 'clusterctl describe cluster $CLUSTER_NAME'..."
  output=$(clusterctl describe cluster "$CLUSTER_NAME" --echo)

  echo "📄 Parsing status from clusterctl output..."

  # Check Cluster readiness
  cluster_ready=$(echo "$output" | grep -A1 "^Cluster/$CLUSTER_NAME" | grep -q "True" && echo "True" || echo "False")
  infra_ready=$(echo "$output" | grep -A1 "ClusterInfrastructure - HetznerCluster/$CLUSTER_NAME" | grep -q "True" && echo "True" || echo "False")
  cp_ready=$(echo "$output" | grep -A1 "ControlPlane - KubeadmControlPlane/$CLUSTER_NAME-control-plane" | grep -q "True" && echo "True" || echo "False")

  echo "🔎 Status:"
  echo "  - Cluster Resource ............: $cluster_ready"
  echo "  - Infrastructure (Hetzner) ....: $infra_ready"
  echo "  - Control Plane ...............: $cp_ready"

  if [[ "$cluster_ready" == "True" && "$infra_ready" == "True" && "$cp_ready" == "True" ]]; then
    echo "✅ All top-level Cluster API resources are READY."
    break
  fi

  echo "⏳ Waiting for resources to become ready..."
  sleep 10
done
