#!/bin/bash

set -eo pipefail

# Generate Kind Config File

stat /tmp/kind.yaml >/dev/null 2>&1 ||
cat <<EOF >/tmp/kind.yaml
---
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster
name: kind
networking:
  apiServerAddress: 127.0.0.1
  apiServerPort: 6443
  disableDefaultCNI: true
  ipFamily: ipv4
featureGates:
  UserNamespacesSupport: true
nodes:
  - role: control-plane
    extraMounts:
      - hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
        listenAddress: 0.0.0.0
      - containerPort: 443
        hostPort: 443
        protocol: TCP
        listenAddress: 0.0.0.0
      - containerPort: 30443
        hostPort: 30443
        protocol: TCP
        listenAddress: 0.0.0.0
EOF

# Create Management Cluster

grep -qa k0rdent-management-local <(kind get clusters) >/dev/null 2>&1 ||
kind create cluster \
  --config /tmp/kind.yaml \
  --name k0rdent-management-local

# Remove Default StorageClass

if kubectl get sc standard >/dev/null 2>&1; then
  kubectl delete deployment local-path-provisioner --namespace local-path-storage
  kubectl delete namespace local-path-storage
  kubectl delete sc standard
fi

# Install Cilium

cilium status >/dev/null 2>&1 || cilium install --helm-release-name cni --wait

# Install KCM

grep -qa kcm <(helm list -n kcm-system) >/dev/null 2>&1 ||
helm upgrade kcm oci://ghcr.io/k0rdent/kcm/charts/kcm \
  --atomic \
  --create-namespace \
  --install \
  --namespace kcm-system \
  --set flux2.kustomizeController.create=true \
  --set 'flux2.kustomizeController.container.additionalArgs[0]=--watch-label-selector=k0rdent.mirantis.com/managed=true' \
  --wait

echo "Waiting for KCM to be ready..."
kubectl wait \
  --for condition=Ready \
  --namespace kcm-system \
  --timeout 720s \
  Management/kcm

# Deploy Management Workload

timeout_duration=60  # Set the timeout duration in seconds
max_retries=100      # Set the maximum number of retries

for ((i=1; i<=max_retries; i++)); do
  if timeout ${timeout_duration} kubectl apply -f <(kustomize build); then
    break
  else
    echo "Attempt $i failed. Retrying in 10 seconds..."
    sleep 10
  fi
done

if [ $i -gt ${max_retries} ]; then
  echo "Command failed after ${max_retries} attempts."
  exit 1
fi

kustomize build ./kcm | kubectl apply -f -

# Create Workload Cluster

kustomize build ./cluster | kubectl apply -f -

# Wait for kubeconfig to be created
echo "Waiting for kubeconfig to be created..."
while true; do
  secret_name=$(kubectl get secret -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep kubeconfig | head -n1)
  if [[ -n "${secret_name}" ]]; then
    echo "Secret ${secret_name} found."
    break
  fi
  echo "Secret not found. Retrying in 5 seconds..."
  sleep 5
done

# Export the kubeconfig from the secret to hack/kubeconfig.yaml
kubectl get secret dev-docker-kubeconfig -o jsonpath='{.data.value}' | base64 --decode > hack/kubeconfig.yaml
echo "Exported kubeconfig to hack/kubeconfig.yaml"
