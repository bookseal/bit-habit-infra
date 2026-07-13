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

## How things deploy

Kubernetes does **not** watch GitHub — it only keeps a declared state true. So
something outside the cluster has to say "there is new code." Two layers, two
answers:

| What changed | Lives in | How it reaches the cluster |
|---|---|---|
| **App content** (pages, code) | each app's own repo | **automatic** — a GitHub Actions workflow SSHes in on every push to `main` and pulls |
| **Infrastructure** (Ingress, certs, Deployments) | **this repo** | **manual `kubectl apply`.** It changes rarely, and a bad Ingress can take every site down at once — a human stays in the loop |

The app-side deploy key is pinned in the server's `authorized_keys` with a
**forced command**, so that key can run one script and nothing else — a leak
gains an attacker nothing but a redeploy. Three repos ship this way today:

| Repo | Site | What its deploy does |
|---|---|---|
| [`portfolio-bithabit`](https://github.com/bookseal/portfolio-bithabit) | `bit-habit.com` | `git pull` — that's the whole deploy |
| [`llm-app-lab`](https://github.com/bookseal/llm-app-lab) | `llm-app-lab.bit-habit.com` | `git pull` |
| [`physical-spark`](https://github.com/bookseal/physical-spark) | `physical-spark.bit-habit.com` | pull → rebuild the auth image if `auth/` changed → `kubectl apply` its own manifests ([`ops/deploy.sh`](https://github.com/bookseal/physical-spark/blob/main/ops/deploy.sh)) |

Static sites are live the instant the pull finishes: nginx serves the git
checkout straight off the disk via a `hostPath` mount, so there is no image to
build and no Pod to restart (~10s end to end).

> **On ArgoCD:** [`apps/argocd/`](apps/argocd/) and
> [`docs/argocd-guide.md`](docs/argocd-guide.md) are kept as a **reference — not
> installed.** There is no `argocd` namespace on the cluster. For a single node
> run by one person, ArgoCD adds more moving parts than it removes; the
> self-healing property it is prized for is already had by re-applying manifests
> on every deploy (`apply` is idempotent).

## Where physical-spark lives

`physical-spark` is the one service whose manifests do **not** live here — they
ship from [its own repo](https://github.com/bookseal/physical-spark) (`k8s/`,
`auth/k8s/`) and are applied by its own deploy script. It also brings its own
Ingress instead of a rule in [`base/ingress.yaml`](base/ingress.yaml). That is a
deliberate trade: the service stays self-contained and deploys end-to-end from
one push, at the cost of this repo no longer being the complete picture.

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
