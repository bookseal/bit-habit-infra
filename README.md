# bit-habit-infra

Infrastructure for every **`*.bit-habit.com`** service — one Oracle Cloud ARM
server running **k3s + Traefik + cert-manager**. All plain YAML, one repo.

> **See it live and explained → [infra.bit-habit.com](https://infra.bit-habit.com)**
> — the architecture, a walkthrough of one request, and live service status, in
> layers (10 seconds → 1 hour). Full status page: **[status.bit-habit.com](https://status.bit-habit.com)**.

---

## What this is

- One small server (OCI Ampere A1, ARM, free tier) runs ~20 sites.
- **Traefik** takes every request on ports 80/443 and routes it by hostname.
- **cert-manager** issues a single wildcard TLS cert (`*.bit-habit.com`,
  Let's Encrypt via Route53 DNS-01) that every subdomain shares.
- **Wildcard DNS** (`*.bit-habit.com → the server`) means a new site needs only
  one Ingress rule — no DNS change.
- Deploys are **manual `kubectl apply`** (no ArgoCD).

## Repo layout

```
base/           cluster-wide
  ingress.yaml            routing: every subdomain → its Service
  cert-manager/           TLS: Let's Encrypt + Route53 (issuer, certificate)
  middlewares/            Traefik middlewares (e.g. strip /api prefix)
apps/<name>/    one folder per service
  deployment.yaml         the app (Deployment + Service, sometimes Ingress)
k3s-bootstrap/  host-level setup
  traefik-config.yaml     Traefik on hostPort 80/443 + http→https redirect
  *.example               install script and config samples
docs/           the infra.bit-habit.com site (index.html) + guides
```

## Add a new service

1. Write `apps/myapp/deployment.yaml` — a Deployment + a Service.
2. Add one rule to [`base/ingress.yaml`](base/ingress.yaml): `myapp.bit-habit.com → myapp-svc`.
3. `kubectl apply -f apps/myapp/ -f base/ingress.yaml`. The wildcard DNS and TLS
   already cover the new subdomain, so it is live over HTTPS right away.

## Key files

| File | What it defines |
|------|-----------------|
| [`k3s-bootstrap/traefik-config.yaml`](k3s-bootstrap/traefik-config.yaml) | the edge — Traefik on 80/443, http→https redirect |
| [`base/ingress.yaml`](base/ingress.yaml) | the routing table — every subdomain → its Service |
| [`base/cert-manager/cluster-issuer.yaml`](base/cert-manager/cluster-issuer.yaml) | how TLS is issued (Let's Encrypt + Route53 DNS-01) |
| [`base/cert-manager/certificate.yaml`](base/cert-manager/certificate.yaml) | the wildcard `*.bit-habit.com` certificate |
| [`apps/llm-app-lab/deployment.yaml`](apps/llm-app-lab/deployment.yaml) | a minimal app — Deployment + Service |
| [`apps/gatus/deployment.yaml`](apps/gatus/deployment.yaml) | the status page — Deployment + Service + ConfigMap |

More depth: [`docs/kubernetes-guide.md`](docs/kubernetes-guide.md).

## Secrets

Real secrets are **gitignored** — never commit them. For each one, commit a
redacted `*.example.yaml` template, copy it to the real filename, and fill it in.
Example: [`base/cert-manager/aws-secret.example.yaml`](base/cert-manager/aws-secret.example.yaml)
(the Route53 credentials cert-manager uses).

---

One server · ~20 sites · one wildcard cert · $0/month.
