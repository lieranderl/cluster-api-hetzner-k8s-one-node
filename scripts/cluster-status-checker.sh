#!/bin/bash

echo
echo "👷 Building cluster on Hetzner. Could take several minutes..."
echo "🔍 Checking Cluster API resource readiness for cluster: $CLUSTER_NAME"
echo

spinner=( '.' ':' 'o' 'O' '@' '*' )
i=0

while true; do
  output=$(clusterctl describe cluster "$CLUSTER_NAME" --echo)

  cluster_ready=$(echo "$output" | grep -A1 "^Cluster/$CLUSTER_NAME" | grep -q "True" && echo "✔" || echo "✖")
  infra_ready=$(echo "$output" | grep -A1 "ClusterInfrastructure - HetznerCluster/$CLUSTER_NAME" | grep -q "True" && echo "✔" || echo "✖")
  cp_ready=$(echo "$output" | grep -A1 "ControlPlane - KubeadmControlPlane/$CLUSTER_NAME-control-plane" | grep -q "True" && echo "✔" || echo "✖")

  spin="${spinner[$i]}"
  printf "\r[%s] Cluster: %s | Infra: %s | ControlPlane: %s" "$spin" "$cluster_ready" "$infra_ready" "$cp_ready"

  if [[ "$cluster_ready" == "✔" && "$infra_ready" == "✔" && "$cp_ready" == "✔" ]]; then
    echo -e "\n✅ All top-level Cluster API resources are READY."
    break
  fi

  i=$(( (i + 1) % ${#spinner[@]} ))
  sleep 0.3
done
