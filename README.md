# bit-habit-infra

Kubernetes manifests for bit-habit.com infrastructure.

## Structure

```
bit-habit-infra/
├── base/                    # Cluster-wide resources
│   ├── ingress.yaml         # Main Traefik ingress
│   ├── cert-manager/        # TLS certificates
│   └── middlewares/         # Traefik middlewares
├── apps/                    # Application deployments
│   ├── bithabit-api/
│   ├── booktoss/
│   ├── code-server/
│   ├── ghost/
│   ├── kubernetes-dashboard/
│   ├── startpage/
│   ├── static-web/
│   ├── viz-platform/
│   └── wikijs/
└── overlays/                # Environment-specific configs
    └── prod/
```

## Usage

```bash
# Apply all base resources
kubectl apply -f base/

# Apply specific app
kubectl apply -f apps/startpage/

# Apply all apps
kubectl apply -f apps/ --recursive
```

## Domains

| Domain | Service |
|--------|---------|
| bit-habit.com | static-web |
| blog.bit-habit.com | ghost |
| startpage.bit-habit.com | startpage |
| wiki.bit-habit.com | wikijs |
| habit.bit-habit.com | static-web + bithabit-api |
| booktoss.bit-habit.com | booktoss |
| viz.bit-habit.com | viz-platform |
| k8s.bit-habit.com | kubernetes-dashboard |