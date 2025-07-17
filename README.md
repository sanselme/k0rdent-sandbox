# K0rdent Demo

This repository demonstrates how to set up a Kubernetes cluster using `kind`, deploy KCM (Kubernetes Cluster Manager), and manage workloads.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Setup Instructions](#setup-instructions)
  - [1. Generate Kind Config File](#1-generate-kind-config-file)
  - [2. Create Management Cluster](#2-create-management-cluster)
  - [3. Install KCM](#3-install-kcm)
  - [4. Deploy Management Workload](#4-deploy-management-workload)
  - [5. Create Workload Cluster](#5-create-workload-cluster)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)

---

## Overview

This guide walks you through setting up a Kubernetes environment using `kind` (Kubernetes in Docker) and deploying workloads with KCM. It includes optional steps for customizing your setup.

---

## Prerequisites

Before starting, ensure you have the following installed on your system:

- [Docker](https://www.docker.com/)
- [Kind](https://kind.sigs.k8s.io/)
- [Kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/)

---

## Setup Instructions

### 1. Generate Kind Config File

Run the following command to generate a `kind` configuration file:

```shell
stat /tmp/kind.yaml >/dev/null 2>&1 ||
cat <<EOF >/tmp/kind.yaml
---
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster
name: kind
networking:
  apiServerAddress: 127.0.0.1
  apiServerPort: 6443
featureGates:
  UserNamespacesSupport: true
nodes:
  - role: control-plane
    extraMounts:
      - # We are mounting the Docker socket to allow KCM to manage containers
        # on the host system (for DockerCluster).
        hostPath: /var/run/docker.sock
        containerPath: /var/run/docker.sock
    extraPortMappings:
      # - containerPort: 80
      #   hostPort: 80
      #   protocol: TCP
      #   listenAddress: 0.0.0.0
      # - containerPort: 443
      #   hostPort: 443
      #   protocol: TCP
      #   listenAddress: 0.0.0.0
      - # Port for KCM management
        containerPort: 30443
        hostPort: 30443
        protocol: TCP
        listenAddress: 0.0.0.0
EOF
```

### 2. Create Management Cluster

Create a management cluster using the generated configuration:

```shell
grep -qa k0rdent-management-local <(kind get clusters) >/dev/null 2>&1 ||
kind create cluster \
  --config /tmp/kind.yaml \
  --name k0rdent-management-local
```

### 3. Install KCM

Deploy KCM using Helm:

```shell
kcm_templates_url=oci://ghcr.io/k0rdent/kcm/charts
kcm_version=1.1.1

# deploy helm chart
helm upgrade kcm $kcm_templates_url/kcm \
  --atomic \
  --create-namespace \
  --install \
  --namespace kcm-system \
  --version $kcm_version \
  --wait

# install kcm management resources
kustomize build ./kcm | kubectl apply -f -

# wait for KCM to be ready
kubectl wait \
  --for condition=Ready \
  --namespace kcm-system \
  --timeout 720s \
  Management/kcm
```

### 4. Deploy Management Workload

Deploy your management workload using `kustomize`:

```shell
timeout_duration=60  # Set the timeout duration in seconds
max_retries=100      # Set the maximum number of retries

PRIVATE_SSH_KEY_B64=$(cat ~/.ssh/id_ed25519 | base64 -w0)
PRIVATE_SSH_KEY_B64="$PRIVATE_SSH_KEY_B64"  envsubst < template/cluster/remote/env.example >template/cluster/remote/.env

for ((i=1; i<=max_retries; i++)); do
  if timeout $timeout_duration kubectl apply -f <(kustomize build); then
    break
  else
    echo "Attempt $i failed. Retrying in 10 seconds..."
    sleep 10
  fi
done

if [ $i -gt $max_retries ]; then
  echo "Command failed after $max_retries attempts."
  exit 1
fi
```

### 5. Create Workload Cluster

Update `cluster/kustomization.yaml` to include the desired cluster by uncommenting the relevant lines. For example:

```yaml
resources:
  - dev-docker.yaml
  # - dev-openstack.yaml
  # - dev-remote.yaml
  # - dev-vsphere.yaml
```

Create a workload cluster:

```shell
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
sed -i '' 's/server: https:\/\/.*:30443/server: https:\/\/127.0.0.1:30443/' hack/kubeconfig.yaml
echo "Exported kubeconfig to hack/kubeconfig.yaml"
```

## Cleanup

To clean up the management cluster and resources, run:

```shell
kubectl delete -f <(kustomize build ./cluster) || true
kind delete cluster --name k0rdent-management-local
rm -f /tmp/kind.yaml /tmp/values.yaml hack/kubeconfig.yaml
```

---

## Troubleshooting

- **Cluster Creation Issues**: Ensure Docker is running and `kind` is installed correctly.
- **KCM Deployment Issues**: Check Helm logs for errors during the KCM installation.

---

## License

Copyright (c) 2025 Schubert Anselme <schubert@anselm.es>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
