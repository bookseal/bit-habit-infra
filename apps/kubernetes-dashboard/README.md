# Kubernetes Dashboard

Web UI for k3s cluster at `k8s.bit-habit.com`

## Installation

```bash
# 1. Install official Kubernetes Dashboard (Helm)
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --create-namespace \
  --namespace kubernetes-dashboard

# 2. Apply ServiceAccount and Ingress
kubectl apply -f deployment.yaml
kubectl apply -f ingress.yaml

# 3. Get login token
kubectl get secret dashboard-admin-token -n kubernetes-dashboard -o jsonpath="{.data.token}" | base64 -d
```

## Access

- **URL**: https://k8s.bit-habit.com
- **Login**: Use token from step 3

## DNS

Add to Cloudflare:
```
k8s.bit-habit.com → (your server IP)
```
