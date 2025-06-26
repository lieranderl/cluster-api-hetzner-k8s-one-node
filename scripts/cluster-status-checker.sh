#!/bin/bash

while true; do
  # Get cluster status and parse for top-level READY lines
  output=$(clusterctl describe cluster "$CLUSTER_NAME" --echo)

  # Extract READY status for Cluster, ClusterInfrastructure, and ControlPlane
  cluster_ready=$(echo "$output" | grep -A1 "^Cluster/$CLUSTER_NAME" | grep -q "True" && echo "True" || echo "False")
  infra_ready=$(echo "$output" | grep -A1 "ClusterInfrastructure - HetznerCluster/$CLUSTER_NAME" | grep -q "True" && echo "True" || echo "False")
  cp_ready=$(echo "$output" | grep -A1 "ControlPlane - KubeadmControlPlane/$CLUSTER_NAME-control-plane" | grep -q "True" && echo "True" || echo "False")

  # Print current status for debugging
  echo "Cluster: $cluster_ready, Infra: $infra_ready, ControlPlane: $cp_ready"

  # Exit if all top-level resources are READY: True
  if [[ "$cluster_ready" == "True" && "$infra_ready" == "True" && "$cp_ready" == "True" ]]; then
    echo "All top-level resources are READY. Proceeding..."
    break
  fi

  sleep 10
done
