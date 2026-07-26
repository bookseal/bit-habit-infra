# bit-habit-infra

Infrastructure for every **`*.bit-habit.com`** service — one Oracle Cloud ARM
server running **k3s + Traefik + cert-manager**. All plain YAML: the edge, TLS,
the routing table, and 17 apps live here. A couple of services keep their
manifests in their own repo ([see below](#services-whose-manifests-live-elsewhere)).

> **See it live and explained → [infra.bit-habit.com](https://infra.bit-habit.com)**
> — the architecture, a walkthrough of one request, and live service status, in
> layers (10 seconds → 1 hour). It also covers
> [every config path](https://infra.bit-habit.com/#paths), a
> [GitOps/ArgoCD primer](https://infra.bit-habit.com/#gitops),
> [what this platform still needs](https://infra.bit-habit.com/#grow), and a
> [glossary of every term](https://infra.bit-habit.com/#glossary) used here.
> Full status page: **[status.bit-habit.com](https://status.bit-habit.com)**.

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

### Where container images come from

The apps that *aren't* static run from a **Docker registry on the host itself**,
at `localhost:5000`. Its catalog is the list of things built here:

```
$ curl -s http://localhost:5000/v2/_catalog
{"repositories":["bithabit-api","booktoss","daily-seongsu","mentoring-api",
                 "pr-auth","sentinel","seoul-apt-price","startpage","viz-bit-habit"]}
```

So those Deployments say `image: localhost:5000/<name>:latest` with
`imagePullPolicy: IfNotPresent`. This was undocumented until 2026-07-26, and the
cost of that was concrete: the manifests had drifted to
`docker.io/library/<name>:latest` — a path that cannot exist, since `library/`
is Docker Hub's namespace for official images — and nobody noticed, because the
cluster was never re-applied from them.

The registry is a `registry:2` container on the host, bound to `127.0.0.1:5000`
only — never reachable from outside. k3s is told where to find it by
[`k3s-bootstrap/registries.yaml.example`](k3s-bootstrap/registries.yaml.example),
which maps `localhost:5000` to `http://127.0.0.1:5000` over plain HTTP.

**Getting a new image in** is three commands — build, push, restart:

```bash
docker build -t localhost:5000/<name>:latest <dir>/
docker push localhost:5000/<name>:latest
sudo k3s kubectl rollout restart deploy/<name>
```

Two apps do this automatically, from their own repos, triggered by the SSH
forced command described above — see
[`mentoring/ops/deploy.sh`](https://github.com/bookseal/mentoring/blob/main/ops/deploy.sh)
and [`physical-spark/ops/deploy.sh`](https://github.com/bookseal/physical-spark/blob/main/ops/deploy.sh).
Both build only when the source directory actually changed, and both fall back
to building when the image is simply missing, so a rebuilt box self-heals rather
than landing in `ImagePullBackOff`. **The other seven are deployed by hand** —
those repos have no deploy script.

> **The restart only picks up new code if the Deployment says
> `imagePullPolicy: Always`.** With `IfNotPresent`, containerd already has
> something tagged `:latest`, so it will not fetch the one just pushed and the
> restart quietly re-runs the old code. The two automated apps get this right
> (`Always`); the seven hand-deployed ones are still on `IfNotPresent` — a
> latent trap, not yet an outage. Recorded here as-is; changing it is a cluster
> change and belongs in its own commit.

**Why the manifests had drifted:** before this registry existed, images were
side-loaded straight into containerd —
`docker build -t sentinel:latest . && docker save sentinel:latest | k3s ctr images import -`.
That workflow needs exactly what the old manifests said: a bare tag with no
registry host, and `imagePullPolicy: Never` (there was nowhere to pull *from*).
The registry replaced it; the manifests were never updated. They were not wrong
— they were **fossils of a workflow that no longer runs**.

> **On ArgoCD:** [`apps/argocd/`](apps/argocd/) and
> [`docs/argocd-guide.md`](docs/argocd-guide.md) are kept as a **reference — not
> installed.** There is no `argocd` namespace on the cluster. For a single node
> run by one person, ArgoCD adds more moving parts than it removes; the
> self-healing property it is prized for is already had by re-applying manifests
> on every deploy (`apply` is idempotent).

## Services whose manifests live elsewhere

This repo is not a complete inventory of the cluster, and that is on purpose.
Two services keep their Kubernetes manifests **next to their own code** — a
standard layout, not a gap: the service stays self-contained and deploys
end-to-end from one push, at the cost of this repo no longer being the whole
picture.

| Service | Repo | Manifests |
|---|---|---|
| `physical-spark` | [bookseal/physical-spark](https://github.com/bookseal/physical-spark) | `k8s/`, `auth/k8s/`, applied by its own [`ops/deploy.sh`](https://github.com/bookseal/physical-spark/blob/main/ops/deploy.sh). Brings its own Ingress instead of a rule in [`base/ingress.yaml`](base/ingress.yaml) |
| `quali-fit` | [KIBA-Automation/quali-fit](https://github.com/KIBA-Automation/quali-fit) | `k8s/` (namespace, PVC, Deployment, Service, middleware, Ingress). Its image is tagged with the git commit it was built from, so a running Pod always names its own source |

Two more — `plane` and `fider` — are **off-the-shelf upstream apps**
(`makeplane/plane`, `getfider/fider`) deployed from a couple of hand-written
YAML files that currently live only on the server, in no repo. Nothing in them
is bespoke, so recreating them means an hour with the upstream docs. Worth
committing into `apps/` eventually; not worth calling a risk.

The one thing genuinely outside git is **secrets** — see [Secrets](#secrets)
below, and [the gap](https://infra.bit-habit.com/#grow).

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
