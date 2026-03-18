# k3s-bootstrap

This directory is the **host-side bootstrap layer** for the cluster.

It exists to answer questions that the workload manifests cannot answer:

- How is k3s installed on the server?
- What belongs in `/etc/rancher/k3s/config.yaml`?
- What belongs in `/etc/rancher/k3s/registries.yaml`?
- Where does the generated kubeconfig live?

This directory is intentionally separate from `base/` and `apps/`.

- `k3s-bootstrap/` is for the server and k3s runtime
- `base/` and `apps/` are for Kubernetes resources running inside that cluster

## Files in this Directory

- `config.yaml.example`
  - Example k3s server config
  - Maps to `/etc/rancher/k3s/config.yaml`
- `registries.yaml.example`
  - Example private registry / mirror config
  - Maps to `/etc/rancher/k3s/registries.yaml`
- `install-server.sh.example`
  - Example installation command for a server node

## Important Runtime Paths

- `/etc/rancher/k3s/config.yaml`
  - Main k3s config file
- `/etc/rancher/k3s/registries.yaml`
  - Registry configuration
- `/etc/rancher/k3s/k3s.yaml`
  - Generated admin kubeconfig
- `/var/lib/rancher/k3s/server/manifests/`
  - Auto-applied manifests watched by k3s

## Suggested Workflow

1. Edit `config.yaml.example` until it matches your intended cluster settings.
2. Copy it to the server as `/etc/rancher/k3s/config.yaml`.
3. If needed, copy `registries.yaml.example` to `/etc/rancher/k3s/registries.yaml`.
4. Install or restart k3s.
5. Use the generated kubeconfig to apply `base/` and `apps/`.

## What This Directory Does Not Do

- It does not automatically install k3s.
- It does not automatically sync files to the server.
- It is not a `kubectl apply` target.

Treat it as the missing "cluster bootstrap notebook" for this repo.
