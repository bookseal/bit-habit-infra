# Headlamp

Modern Kubernetes web UI for `k8s.bit-habit.com`.

This repo pins Headlamp to `v0.40.1`.

## Install

```bash
kubectl apply -f deployment.yaml
kubectl apply -f ../oauth2-proxy/
```

## Access

- URL: `https://k8s.bit-habit.com`
- Auth: GitHub via `oauth2-proxy`
- Cluster access: `headlamp-admin` service account with `cluster-admin`

## Notes

- Headlamp runs in-cluster.
- An init container writes a kubeconfig for the `headlamp-admin` service account.
- `oauth2-proxy` protects the public URL.
- Headlamp is the only admin UI tracked in this repo.
- Headlamp can inspect cluster resources and open pod-level exec sessions, but this deployment does not add a general-purpose browser shell or arbitrary `kubectl` terminal.
