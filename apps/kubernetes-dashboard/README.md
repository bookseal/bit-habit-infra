# Kubernetes Dashboard (Legacy)

Legacy web UI reference for k3s cluster.

`k8s.bit-habit.com` now uses Headlamp.
Keep this directory only as a fallback reference.

## What This Directory Still Contains

- `deployment.yaml`: admin service account and token secret for legacy dashboard access
- `ingress-direct.yaml.disabled`: disabled direct Traefik route for the old dashboard

## Legacy Access

If you want to bring the old dashboard back for debugging:

```bash
kubectl get secret dashboard-admin-token -n kubernetes-dashboard -o jsonpath="{.data.token}" | base64 -d
```

Use that token in the legacy dashboard after enabling its direct route again.

## DNS

Add to Cloudflare:
```
k8s.bit-habit.com → (your server IP)
```
