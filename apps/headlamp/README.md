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
- The old Kubernetes Dashboard setup is left in the repo only as a fallback reference.
