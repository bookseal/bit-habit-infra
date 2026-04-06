# bit-habit-infra

> GitOps infrastructure for a single-node k3s cluster on Oracle Cloud (OCI Ampere A1).  
> All services at `*.bit-habit.com` are defined here and auto-deployed by ArgoCD.

**14 services · $0/month · Zero manual kubectl apply**

![Headlamp cluster map](assets/headlamp-cluster-map.png)

---

## Why This Exists

Every side project I build gets deployed with a custom domain. If it's not live, I don't care about it.

But managing 10+ projects with separate Nginx configs got messy fast. So I built a proper platform:

| Before | After |
|---|---|
| AWS EC2 (paid) | **OCI Ampere A1 (free tier)** |
| Manual Nginx config × 10 | **k3s + Traefik auto-routing** |
| Manual SSL renewal | **cert-manager auto-renewal (every 60 days)** |
| Manual kubectl apply | **ArgoCD GitOps auto-sync** |
| ~$50/month | **$0/month** |

**Git is the single source of truth.** No manual `kubectl apply`. Ever.

---

## Architecture

```mermaid
flowchart TB
    subgraph Internet
        USER["Browser"]
        DNS["Route53 DNS\n*.bit-habit.com"]
    end

    subgraph OCI["Oracle Cloud — Ampere A1"]
        subgraph K3S["k3s Cluster"]
            TRAEFIK["Traefik\nIngress Controller\n:443 TLS termination"]
            CM["cert-manager\nLet's Encrypt wildcard"]

            subgraph NS_DEFAULT["namespace: default"]
                API["bithabit-api\nFastAPI"]
                GHOST["ghost\nBlog"]
                WIKI["wikijs\nKnowledge base"]
                BOOKTOSS["booktoss\nBook search"]
                STATIC["static-web\nNginx"]
                CODE["code-server\nBrowser IDE"]
                START["startpage\nDashboard"]
                VIZ["viz-platform\nStreamlit"]
                DAILY["daily-seongsu\nGradio ML"]
                SENTINEL["sentinel\nGradio AI"]
                SEOUL["seoul-apt-price\nStreamlit ML"]
            end

            subgraph NS_HEADLAMP["namespace: headlamp"]
                OAUTH["oauth2-proxy\nGitHub SSO"]
                HL["headlamp\nCluster UI"]
            end

            subgraph NS_ARGOCD["namespace: argocd"]
                ARGO["ArgoCD\nGitOps controller"]
            end
        end
    end

    subgraph GitHub
        REPO["bookseal/bit-habit-infra\nmain branch"]
    end

    USER -->|"https://blog.bit-habit.com"| DNS
    DNS -->|"server IP"| TRAEFIK
    CM -->|"tls-secret"| TRAEFIK
    TRAEFIK --> NS_DEFAULT
    TRAEFIK --> OAUTH --> HL
    REPO -->|"watch & auto-sync"| ARGO
    ARGO -->|"apply manifests"| K3S
```

---

## GitOps Workflow

```mermaid
sequenceDiagram
    actor Dev as Developer
    participant Git as GitHub<br/>bit-habit-infra
    participant Argo as ArgoCD
    participant K8s as k3s Cluster

    Dev->>Git: git push (edit manifest)
    Git-->>Argo: webhook / poll (3min)
    Argo->>Argo: diff: Git vs Live
    alt Drift detected
        Argo->>K8s: kubectl apply (auto-sync)
        K8s-->>Argo: resource updated
        Argo-->>Git: status: Synced ✅
    else No change
        Argo-->>Git: status: Synced ✅
    end

    Note over Dev,K8s: Rollback = git revert + push
```

---

## How to Deploy

### Add a new service

```mermaid
flowchart TD
    A["1. Write Dockerfile"] --> B["2. Build & import image\ndocker build → nerdctl load"]
    B --> C["3. Create apps/myapp/\ndeployment.yaml + service.yaml"]
    C --> D["4. Add ingress rule\nbase/ingress.yaml"]
    D --> E["5. git push"]
    E --> F["6. ArgoCD auto-syncs"]
    F --> G["7. https://myapp.bit-habit.com ✅"]
```

### Update an existing service

```
docker build -t myapp:latest .
→ nerdctl -n k8s.io load < myapp.tar
→ kubectl rollout restart deploy/myapp
→ Rolling update (zero downtime)
```

### Roll back

```
git revert + push → ArgoCD syncs to previous state
```

---

## TLS Certificates

```mermaid
sequenceDiagram
    participant CM as cert-manager
    participant R53 as Route53
    participant LE as Let's Encrypt
    participant T as Traefik

    CM->>R53: Create _acme-challenge TXT record
    LE->>R53: Verify TXT record
    R53-->>LE: Record found
    LE-->>CM: Wildcard cert issued (*.bit-habit.com)
    CM->>CM: Store in tls-secret
    T->>CM: Read tls-secret
    Note over CM,T: Auto-renew every 60 days (expires at 90)
```

One wildcard cert covers all subdomains. Fully automatic.

---

## Service Catalog (14 Services)

| Service | Subdomain | Port | Stack |
|---------|-----------|------|-------|
| **sentinel** | sentinel.bit-habit.com | 7860 | Gradio AI assistant |
| **booktoss** | booktoss.bit-habit.com | 8000 | Streamlit + Playwright |
| **bithabit-api** | habit.bit-habit.com/api/* | 8000 | FastAPI + SQLite |
| **static-web** | bit-habit.com, habit, status | 80 | Nginx |
| **ghost** | blog.bit-habit.com | 2368 | Ghost + MySQL |
| **wikijs** | wiki.bit-habit.com | 3000 | Wiki.js + PostgreSQL |
| **viz-platform** | viz.bit-habit.com | 8501 | Streamlit + Manim |
| **seoul-apt-price** | seoul-apt.bit-habit.com | 8501 | Streamlit ML |
| **code-server** | code-server.bit-habit.com | 8080 | VS Code in browser |
| **startpage** | startpage.bit-habit.com | 8000 | Custom dashboard |
| **daily-seongsu** | daily-seongsu.bit-habit.com | 7860 | Gradio ML |
| **headlamp** | k8s.bit-habit.com | 4466 | Cluster dashboard |
| **oauth2-proxy** | k8s.bit-habit.com (gate) | 4180 | GitHub SSO |
| **argocd** | argocd.bit-habit.com | — | GitOps controller |

---

## Design Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| **GitOps tool** | ArgoCD | Auto-sync, drift detection, self-heal, web UI |
| **Ingress** | Single `base/ingress.yaml` | One routing table — easy to audit |
| **TLS** | Wildcard via DNS-01 | One cert for all subdomains |
| **Storage** | hostPath | Single node — simple and enough |
| **Image pull** | `Never` (local builds) | No registry needed |
| **Cost** | OCI free tier | ARM64, 4 cores, 24GB RAM — $0/month |

---

## Cluster Layout

```mermaid
flowchart TB
    subgraph NODE["k3s Node (OCI Ampere A1)"]
        direction TB
        subgraph CP["Control Plane"]
            APISERVER["API Server"]
            SCHED["Scheduler"]
            CTRL["Controller Manager"]
            SQLITE[("SQLite\n(replaces etcd)")]
        end

        subgraph SYSTEM["kube-system"]
            TRAEFIK["Traefik"]
            COREDNS["CoreDNS"]
            METRICS["metrics-server"]
        end

        subgraph WORKLOADS["Workloads"]
            DEFAULT["default\n11 services"]
            HEADLAMP_NS["headlamp\noauth2-proxy + UI"]
            ARGOCD_NS["argocd\nGitOps controller"]
            CERTMGR_NS["cert-manager\nTLS automation"]
        end

        APISERVER <--> SQLITE
        APISERVER --> SCHED
        APISERVER --> CTRL
        CTRL --> WORKLOADS
    end
```

---

## Repo Structure

```
bit-habit-infra/
├── base/                          # Cluster-wide infra
│   ├── ingress.yaml               #   Routing: subdomain → service
│   ├── cert-manager/              #   TLS: Let's Encrypt + Route53
│   │   ├── cluster-issuer.yaml
│   │   ├── certificate.yaml
│   │   └── aws-secret.yaml
│   └── middlewares/
│       └── strip-api-middleware.yaml
│
├── apps/                          # Per-service deployments
│   ├── argocd/
│   ├── bithabit-api/
│   ├── booktoss/
│   ├── code-server/
│   ├── daily-seongsu/
│   ├── ghost/
│   ├── headlamp/
│   ├── oauth2-proxy/
│   ├── seoul-apt-price/
│   ├── sentinel/
│   ├── startpage/
│   ├── static-web/
│   ├── viz-platform/
│   └── wikijs/
│
├── k3s-bootstrap/                 # Host-level setup
│
├── docs/
│   ├── kubernetes-guide.md        # Zero-to-advanced k8s guide
│   └── argocd-guide.md            # ArgoCD setup & ops
│
└── assets/
    └── headlamp-cluster-map.png
```

---

## Docs

| Document | What's inside |
|----------|---------------|
| [Kubernetes Guide](docs/kubernetes-guide.md) | Learn k8s from scratch using this cluster as a live example |
| [ArgoCD Guide](docs/argocd-guide.md) | Setup, architecture, daily ops, CLI, troubleshooting |

---

Built on OCI Ampere A1. Managed by ArgoCD. $0/month.
