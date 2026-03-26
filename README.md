# bit-habit-infra

> GitOps infrastructure for a single-node k3s cluster on Oracle Cloud (OCI Ampere A1).
> All services at `*.bit-habit.com` are defined here and auto-deployed by ArgoCD.

![Headlamp cluster map](assets/headlamp-cluster-map.png)

---

## Architecture Overview

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
                GHOST["ghost\nBlog CMS"]
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

This is the standard deployment flow. **Git is the single source of truth** — no manual `kubectl apply`.

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

### ArgoCD Applications

```mermaid
flowchart LR
    subgraph REPO["bit-habit-infra (GitHub)"]
        BASE["base/\ningress, cert-manager,\nmiddlewares"]
        APPS["apps/\nall service deployments"]
    end

    subgraph ARGO["ArgoCD"]
        A1["bit-habit-base\nselfHeal: true"]
        A2["bit-habit-apps\nselfHeal: true"]
    end

    BASE --> A1
    APPS --> A2
    A1 -->|sync| CLUSTER["k3s cluster"]
    A2 -->|sync| CLUSTER
```

---

## Traffic Flow

How a request reaches your app — every hop from browser to container:

```mermaid
flowchart LR
    A["Browser\nhttps://blog.bit-habit.com"] --> B["Route53\nDNS A record → server IP"]
    B --> C["Traefik :443\nTLS termination\n(tls-secret from cert-manager)"]
    C --> D["Ingress rules\nbase/ingress.yaml"]
    D --> E["Service\nghost-svc:80\n(ClusterIP, iptables DNAT)"]
    E --> F["Pod\nghost:5-alpine\n:2368"]
    F --> G["Volume\nhostPath on host"]
```

### TLS Certificate Lifecycle

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

---

## Service Catalog

| Service | Subdomain | Port | Stack | Directory |
|---------|-----------|------|-------|-----------|
| **bithabit-api** | `habit.bit-habit.com/api/*` | 8000 | FastAPI + SQLite | `apps/bithabit-api/` |
| **static-web** | `bit-habit.com`, `habit`, `status` | 80 | Nginx | `apps/static-web/` |
| **ghost** | `blog.bit-habit.com` | 2368 | Ghost + MySQL | `apps/ghost/` |
| **wikijs** | `wiki.bit-habit.com` | 3000 | Wiki.js + PostgreSQL | `apps/wikijs/` |
| **booktoss** | `booktoss.bit-habit.com` | 8000 | Streamlit + Playwright | `apps/booktoss/` |
| **code-server** | `code-server.bit-habit.com` | 8080 | VS Code in browser | `apps/code-server/` |
| **viz-platform** | `viz.bit-habit.com` | 8501 | Streamlit | `apps/viz-platform/` |
| **startpage** | `startpage.bit-habit.com` | 8000 | Custom dashboard | `apps/startpage/` |
| **daily-seongsu** | `daily-seongsu.bit-habit.com` | 7860 | Gradio ML app | `apps/daily-seongsu/` |
| **sentinel** | `sentinel.bit-habit.com` | 7860 | Gradio AI assistant | `apps/sentinel/` |
| **seoul-apt-price** | `seoul-apt.bit-habit.com` | 8501 | Streamlit ML app | `apps/seoul-apt-price/` |
| **headlamp** | `k8s.bit-habit.com` | 4466 | Cluster dashboard | `apps/headlamp/` |
| **oauth2-proxy** | `k8s.bit-habit.com` (gate) | 4180 | GitHub SSO | `apps/oauth2-proxy/` |
| **argocd** | `argocd.bit-habit.com` | — | GitOps controller | `apps/argocd/` |

---

## Repository Structure

```
bit-habit-infra/
├── base/                          # Cluster-wide infrastructure
│   ├── ingress.yaml               #   Main routing: subdomain → service
│   ├── cert-manager/              #   TLS: Let's Encrypt + Route53 DNS-01
│   │   ├── cluster-issuer.yaml
│   │   ├── certificate.yaml
│   │   └── aws-secret.yaml
│   └── middlewares/
│       └── strip-api-middleware.yaml  # Strip /api prefix for FastAPI
│
├── apps/                          # Per-service deployments (ArgoCD watches this)
│   ├── argocd/                    #   ArgoCD Application + Ingress
│   ├── bithabit-api/              #   Deployment + Service
│   ├── booktoss/
│   ├── code-server/
│   ├── daily-seongsu/             #   Deployment + Service + PV/PVC
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
├── k3s-bootstrap/                 # Host-level setup (not applied by k8s)
│   ├── config.yaml.example
│   ├── install-server.sh.example
│   └── registries.yaml.example
│
├── docs/                          # Guides & documentation
│   ├── kubernetes-guide.md        #   K8s beginner's guidebook (zero → advanced)
│   └── argocd-guide.md            #   ArgoCD setup & operations guide
│
└── assets/
    └── headlamp-cluster-map.png
```

---

## Standard Deployment Workflow

### Adding a new service

```mermaid
flowchart TD
    A["1. Write Dockerfile\nin service repo"] --> B["2. Build & import image\n<code>docker build -t myapp:latest .\nnerdctl -n k8s.io load < myapp.tar</code>"]
    B --> C["3. Create apps/myapp/\ndeployment.yaml + service.yaml"]
    C --> D["4. Add ingress rule\nbase/ingress.yaml"]
    D --> E["5. git add, commit, push"]
    E --> F["6. ArgoCD auto-syncs\nPod + Service + Ingress created"]
    F --> G["7. Verify\nhttps://myapp.bit-habit.com"]
```

### Updating an existing service

```mermaid
flowchart TD
    A["1. Rebuild image\n<code>docker build -t myapp:latest .</code>"] --> B["2. Import to k3s\n<code>nerdctl -n k8s.io load < myapp.tar</code>"]
    B --> C["3. Restart deployment\n<code>kubectl rollout restart deploy/myapp</code>"]
    C --> D["4. Rolling update\n(zero downtime)"]

    style D fill:#4CAF50,color:#fff
```

### Rolling back a deployment

```mermaid
flowchart LR
    A["Problem detected"] --> B{"Git-level\nor k8s-level?"}
    B -->|Git| C["git revert + push\nArgoCD auto-syncs"]
    B -->|Quick| D["kubectl rollout undo\ndeploy/myapp"]
```

---

## Cluster Topology

```mermaid
flowchart TB
    subgraph NODE["k3s Node (OCI Ampere A1)"]
        direction TB
        subgraph CP["Control Plane"]
            APISERVER["API Server"]
            SCHED["Scheduler"]
            CTRL["Controller Manager"]
            SQLITE[("SQLite\n(etcd equivalent)")]
        end

        subgraph SYSTEM["kube-system"]
            TRAEFIK["Traefik"]
            COREDNS["CoreDNS"]
            METRICS["metrics-server"]
        end

        subgraph WORKLOADS["Workload Namespaces"]
            DEFAULT["default\n11 services"]
            HEADLAMP_NS["headlamp\noauth2-proxy + headlamp"]
            ARGOCD_NS["argocd\nArgoCD server"]
            CERTMGR_NS["cert-manager\ncert-manager + webhook"]
        end

        APISERVER <--> SQLITE
        APISERVER --> SCHED
        APISERVER --> CTRL
        CTRL --> WORKLOADS
    end
```

---

## Key Design Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| **Manifest location** | Centralized in `bit-habit-infra/apps/` | ArgoCD recommended pattern for single-operator clusters. Single source of truth. |
| **GitOps tool** | ArgoCD | Auto-sync, drift detection, self-heal. Web UI at `argocd.bit-habit.com`. |
| **Ingress** | Single `base/ingress.yaml` | One routing table, one wildcard cert, easy to audit. |
| **TLS** | Wildcard `*.bit-habit.com` via DNS-01 | One cert covers all subdomains. Auto-renewed by cert-manager. |
| **Storage** | `hostPath` volumes | Single-node cluster. Simple and sufficient. Migrate to PVC for multi-node. |
| **Image pull** | `imagePullPolicy: Never` | Local builds imported to containerd. No registry needed. |
| **Secrets** | Out-of-band `kubectl create secret` | Never committed to Git. Consider Sealed Secrets for full GitOps. |

---

## Docs

| Document | Description |
|----------|-------------|
| [Kubernetes Beginner's Guidebook](docs/kubernetes-guide.md) | Zero-to-advanced k8s guide using this cluster as a live example |
| [ArgoCD Guide](docs/argocd-guide.md) | ArgoCD installation, architecture, daily ops, CLI, and troubleshooting |
