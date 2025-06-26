# K0rdent Hack Directory

This directory contains scripts, configuration, and resources for advanced setup, automation, and cluster management tasks for K0rdent.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Setup Instructions](#setup-instructions)
- [Hack Directory Structure](#hack-directory-structure)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Overview

The `hack` directory provides tools and manifests for VM-based cluster setup, CRD generation, KCM configuration, and automation. It is intended for advanced users and contributors who need to customize or automate K0rdent deployments.

---

## Prerequisites

- [Docker](https://www.docker.com/)
- [Kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/)
- [k0sctl](https://docs.k0sproject.io/latest/k0sctl-install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

---

## Setup Instructions

### 1. Create VM with CloudInit

Use `./hack/cloudinit.yaml` to create a VM. Install Docker in the VM to enable `DockerCluster` creation.

```shell
# Linux
apt install genisoimage
genisoimage -joliet -rock -output ./seed.iso -volid cidata ./user-data ./meta-data ./network-config 

# macOS
brew install cdrtools
mkisofs -joliet -rock -output ./seed.iso -volid cidata ./user-data ./meta-data ./network-config 
```

### 2. Generate and Upload CRDs

Generate CRDs and upload them to the VM at `/var/lib/k0s/manifests/crds/`:

  ```shell
  kustomize build 'https://github.com/kubernetes-sigs/gateway-api/config/crd/experimental?ref=v1.2.1' >/var/lib/k0s/manifests/crds/gapi.yaml
  kustomize build 'https://github.com/kubernetes-csi/external-snapshotter/client/config/crd?ref=v8.2.1' >/var/lib/k0s/manifests/crds/es.yaml
  ```

### 3. Configure KCM

Upload `./hack/containerd.toml` to `/etc/k0s/containerd.d/systemd.toml` on the VM.

Apply the cluster configuration and retrieve the kubeconfig:

  ```shell
  k0sctl apply --config ./hack/cluster.yaml
  k0sctl kubeconfig --config ./hack/cluster.yaml > ./hack/kubeconfig.yaml
  ```

See [README](../README.md#6-deploy-management-workload) for to continue with deployment.

---

## Hack Directory Structure

- `cloudinit.yaml`: Cloud-init configuration for VM provisioning.
- `cluster.yaml`: Cluster configuration for k0sctl.
- `containerd.toml`: Containerd configuration for KCM.

---

## Troubleshooting

- **VM Provisioning Issues**: Ensure your cloud provider supports cloud-init and the configuration matches your environment.
- **CRD Generation Errors**: Verify that Kustomize is installed and the URLs are correct.
- **KCM Configuration Problems**: Check file paths and permissions when uploading configuration files to the VM.

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
