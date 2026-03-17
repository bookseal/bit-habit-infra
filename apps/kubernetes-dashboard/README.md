# Kubernetes Dashboard

Web UI for k3s cluster at `k8s.bit-habit.com`

If you use `apps/oauth2-proxy/`, keep the direct dashboard ingress disabled.
Running both ingress routes for the same host causes ambiguous Traefik
routing for `k8s.bit-habit.com`.

## Installation

```bash
# 1. Install official Kubernetes Dashboard (Helm)
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --create-namespace \
  --namespace kubernetes-dashboard

# 2. Apply ServiceAccount and Ingress
kubectl apply -f deployment.yaml
kubectl apply -f auth-proxy.yaml
kubectl apply -f ingress.yaml

# 3. Get login token
kubectl get secret dashboard-admin-token -n kubernetes-dashboard -o jsonpath="{.data.token}" | base64 -d
```

## Access

- **URL**: https://k8s.bit-habit.com
- **Login**: Direct access when used with `apps/oauth2-proxy/`
- **Fallback**: Use token from step 3 for direct dashboard access

## DNS

Add to Cloudflare:
```
k8s.bit-habit.com → (your server IP)
```
