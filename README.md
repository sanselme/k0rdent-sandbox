# K0rdent Demo

This repository demonstrates how to set up a Kubernetes cluster using `kind`, install Cilium, deploy KCM (Kubernetes Cluster Manager), and manage workloads.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Setup Instructions](#setup-instructions)
  - [1. Generate Kind Config File](#1-generate-kind-config-file)
  - [2. Create Management Cluster](#2-create-management-cluster)
  - [3. Remove Default StorageClass](#3-remove-default-storageclass)
  - [4. Install Cilium](#4-install-cilium)
  - [5. Install KCM](#5-install-kcm)
  - [6. Deploy Management Workload](#6-deploy-management-workload)
  - [7. Create Workload Cluster](#7-create-workload-cluster)
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
- [Cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/)

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
```

### 2. Create Management Cluster

Create a management cluster using the generated configuration:

```shell
grep -qa k0rdent-management-local <(kind get clusters) >/dev/null 2>&1 ||
kind create cluster \
  --config /tmp/kind.yaml \
  --name k0rdent-management-local
```

### 3. Remove Default StorageClass

If a default StorageClass exists, remove it:

```shell
if kubectl get sc standard >/dev/null 2>&1; then
  kubectl delete deployment local-path-provisioner --namespace local-path-storage
  kubectl delete namespace local-path-storage
  kubectl delete sc standard
fi
```

### 4. Install Cilium

Install Cilium as the CNI (Container Network Interface):

```shell
cilium status >/dev/null 2>&1 || cilium install --helm-release-name cni --wait
```

### 5. Install KCM

Deploy KCM using Helm:

```shell
helm upgrade kcm oci://ghcr.io/k0rdent/kcm/charts/kcm \
  --atomic \
  --create-namespace \
  --install \
  --namespace kcm-system \
  --set flux2.kustomizeController.create=true \
  --set 'flux2.kustomizeController.container.additionalArgs[0]=--watch-label-selector=k0rdent.mirantis.com/managed=true' \
  --wait
```

Wait for KCM to be ready:

```shell
kubectl wait \
  --for condition=Ready \
  --namespace kcm-system \
  --timeout 720s \
  Management/kcm
```

### 6. Deploy Management Workload

Deploy your management workload using `kustomize`:

```shell
timeout_duration=60  # Set the timeout duration in seconds
max_retries=100      # Set the maximum number of retries

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

kustomize build ./kcm | kubectl apply -f -
```

### 7. Create Workload Cluster

Create a workload cluster:

```shell
kustomize build ./cluster | kubectl apply -f -
```

---

## Troubleshooting

- **Cluster Creation Issues**: Ensure Docker is running and `kind` is installed correctly.
- **Cilium Installation Errors**: Verify that the Cilium CLI is installed and accessible in your PATH.
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
