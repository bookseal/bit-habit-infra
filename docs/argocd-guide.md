# ArgoCD Guide — From Zero to GitOps

> A complete beginner's guide to ArgoCD on this cluster.
> Every section includes a visual diagram. Read at your own pace.

---

## Table of Contents

- [1. What is ArgoCD?](#1-what-is-argocd)
- [2. Why do we need it?](#2-why-do-we-need-it)
- [3. How ArgoCD works — the big picture](#3-how-argocd-works--the-big-picture)
- [4. Architecture — what runs inside the cluster](#4-architecture--what-runs-inside-the-cluster)
- [5. Installation — what we did](#5-installation--what-we-did)
- [6. Accessing the ArgoCD UI](#6-accessing-the-argocd-ui)
  - [6.1 Login credentials](#61-login-credentials)
  - [6.2 Opening the dashboard](#62-opening-the-dashboard)
- [7. Core concepts](#7-core-concepts)
  - [7.1 Application](#71-application)
  - [7.2 Project](#72-project)
  - [7.3 Sync and sync status](#73-sync-and-sync-status)
  - [7.4 Health status](#74-health-status)
- [8. How our repo is connected](#8-how-our-repo-is-connected)
- [9. Daily operations — how to use ArgoCD](#9-daily-operations--how-to-use-argocd)
  - [9.1 Deploying a change](#91-deploying-a-change)
  - [9.2 Checking application status](#92-checking-application-status)
  - [9.3 Manual sync](#93-manual-sync)
  - [9.4 Rolling back a deployment](#94-rolling-back-a-deployment)
  - [9.5 Force refresh](#95-force-refresh)
- [10. Using the ArgoCD CLI](#10-using-the-argocd-cli)
  - [10.1 Login](#101-login)
  - [10.2 List applications](#102-list-applications)
  - [10.3 Sync an application](#103-sync-an-application)
  - [10.4 View application details](#104-view-application-details)
  - [10.5 View sync history](#105-view-sync-history)
  - [10.6 Rollback](#106-rollback)
- [11. The sync process — step by step](#11-the-sync-process--step-by-step)
- [12. Self-heal and auto-prune](#12-self-heal-and-auto-prune)
- [13. Troubleshooting common issues](#13-troubleshooting-common-issues)
- [14. Security best practices](#14-security-best-practices)
- [15. Quick reference cheat sheet](#15-quick-reference-cheat-sheet)

---

## 1. What is ArgoCD?

**ArgoCD** is a GitOps tool for Kubernetes. It watches a Git repository and automatically keeps your cluster in sync with the manifests stored there.

Think of it as an **autopilot** for your cluster: you push a change to Git, and ArgoCD applies it for you.

```mermaid
flowchart LR
    A["👨‍💻 Developer"]:::dev --> B["📝 git push"]:::git
    B --> C["📦 Git Repo"]:::git
    C --> D["🔄 ArgoCD"]:::argo
    D --> E["☸️ Kubernetes Cluster"]:::k8s

    classDef dev fill:#4CAF50,stroke:#388E3C,color:#fff
    classDef git fill:#F44336,stroke:#D32F2F,color:#fff
    classDef argo fill:#FF9800,stroke:#F57C00,color:#fff
    classDef k8s fill:#2196F3,stroke:#1976D2,color:#fff
```

**Without ArgoCD:** You edit YAML → you run `kubectl apply` manually → you hope you did not forget anything.

**With ArgoCD:** You edit YAML → you push to Git → ArgoCD applies it automatically → if something drifts, ArgoCD fixes it.

---

## 2. Why do we need it?

Before ArgoCD, deploying to this cluster meant:

1. SSH into the server
2. `cd` to the repo directory
3. `git pull`
4. `kubectl apply -f ...` for every file that changed
5. Hope you did not miss anything

This is manual, error-prone, and leaves no audit trail beyond Git history.

```mermaid
flowchart TD
    subgraph before["❌ Before ArgoCD"]
        direction TB
        B1["SSH into server"]:::bad --> B2["git pull"]:::bad
        B2 --> B3["kubectl apply -f ..."]:::bad
        B3 --> B4["Did I miss a file? 🤔"]:::bad
    end

    subgraph after["✅ After ArgoCD"]
        direction TB
        A1["git push"]:::good --> A2["ArgoCD detects change"]:::good
        A2 --> A3["Auto-sync to cluster"]:::good
        A3 --> A4["Dashboard shows status ✅"]:::good
    end

    classDef bad fill:#FFCDD2,stroke:#F44336,color:#B71C1C
    classDef good fill:#C8E6C9,stroke:#4CAF50,color:#1B5E20
```

ArgoCD gives you:

| Benefit | What it means |
|---------|---------------|
| **Automatic deployment** | Push to Git → cluster updates itself |
| **Drift detection** | ArgoCD tells you if someone changed something by hand |
| **Self-healing** | If someone deletes a Pod manually, ArgoCD recreates it |
| **Rollback** | One click to go back to any previous version |
| **Visual dashboard** | See all your apps, their health, and sync status |
| **Audit trail** | Every change is a Git commit — who, what, when |

---

## 3. How ArgoCD works — the big picture

ArgoCD continuously compares two things:

1. **Desired state** — the YAML manifests in your Git repo
2. **Live state** — what is actually running in the cluster

If they match → everything is green (**Synced**).
If they differ → ArgoCD flags it (**OutOfSync**) and can auto-fix it.

```mermaid
flowchart LR
    subgraph git["📦 Git Repo (Desired State)"]
        G1["deployment.yaml\nreplicas: 3"]:::git
    end

    subgraph cluster["☸️ Cluster (Live State)"]
        C1["Deployment\nreplicas: 3"]:::synced
    end

    subgraph cluster2["☸️ Cluster (Drifted)"]
        C2["Deployment\nreplicas: 1\n⚠️ Someone scaled down"]:::drift
    end

    G1 -->|"Compare"| C1
    G1 -->|"Compare"| C2

    C1 -.->|"✅ Synced"| OK["All good"]:::ok
    C2 -.->|"❌ OutOfSync"| FIX["ArgoCD re-applies\nreplicas: 3"]:::fix

    classDef git fill:#FF9800,stroke:#F57C00,color:#fff
    classDef synced fill:#4CAF50,stroke:#388E3C,color:#fff
    classDef drift fill:#F44336,stroke:#D32F2F,color:#fff
    classDef ok fill:#C8E6C9,stroke:#4CAF50,color:#1B5E20
    classDef fix fill:#FFF9C4,stroke:#FBC02D,color:#F57F17
```

---

## 4. Architecture — what runs inside the cluster

ArgoCD installs several components in the `argocd` namespace:

```mermaid
flowchart TD
    subgraph argocd_ns["🔷 argocd namespace"]
        direction TB
        SERVER["🌐 argocd-server\n(Web UI + API)"]:::server
        REPO["📂 argocd-repo-server\n(Clones Git repos,\nrenders manifests)"]:::repo
        CTRL["🎮 argocd-application-controller\n(Watches apps,\ndetects drift,\ntriggers sync)"]:::ctrl
        REDIS["🔴 argocd-redis\n(Cache)"]:::redis
        DEX["🔐 argocd-dex-server\n(SSO / authentication)"]:::dex
        NOTIF["🔔 argocd-notifications-controller\n(Slack/email alerts)"]:::notif
        APPSET["📋 argocd-applicationset-controller\n(Generate apps\nfrom templates)"]:::appset
    end

    SERVER --> REPO
    SERVER --> REDIS
    CTRL --> REPO
    CTRL --> REDIS
    SERVER --> DEX

    classDef server fill:#2196F3,stroke:#1976D2,color:#fff
    classDef repo fill:#FF9800,stroke:#F57C00,color:#fff
    classDef ctrl fill:#4CAF50,stroke:#388E3C,color:#fff
    classDef redis fill:#F44336,stroke:#D32F2F,color:#fff
    classDef dex fill:#9C27B0,stroke:#7B1FA2,color:#fff
    classDef notif fill:#00BCD4,stroke:#0097A7,color:#fff
    classDef appset fill:#795548,stroke:#5D4037,color:#fff
```

| Component | Role |
|-----------|------|
| **argocd-server** | The Web UI and API. You interact with this. |
| **argocd-repo-server** | Clones your Git repo and renders the manifests. |
| **argocd-application-controller** | The brain — watches applications, detects drift, triggers sync. |
| **argocd-redis** | In-memory cache for performance. |
| **argocd-dex-server** | Handles SSO and authentication (GitHub, Google, etc.). |
| **argocd-notifications-controller** | Sends alerts when things change (Slack, email, webhook). |
| **argocd-applicationset-controller** | Generates multiple Application resources from templates. |

---

## 5. Installation — what we did

Here is exactly what was done to install ArgoCD on this cluster:

```bash
# 1. Create the namespace
kubectl create namespace argocd

# 2. Install ArgoCD from the official manifests
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  --server-side --force-conflicts

# 3. Patch the server to run in insecure mode (Traefik handles TLS)
kubectl -n argocd patch deployment argocd-server \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'

# 4. Install the ArgoCD CLI (arm64)
curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-arm64
sudo install -m 555 /tmp/argocd /usr/local/bin/argocd

# 5. Apply the Ingress so Traefik routes argocd.bit-habit.com to the server
kubectl apply -f apps/argocd/ingress.yaml

# 6. Apply the Application resources so ArgoCD watches this repo
kubectl apply -f apps/argocd/application.yaml
```

```mermaid
flowchart TD
    A["1️⃣ Create namespace\nkubectl create ns argocd"]:::step --> B["2️⃣ Install manifests\nkubectl apply -f install.yaml"]:::step
    B --> C["3️⃣ Patch server\n--insecure flag"]:::step
    C --> D["4️⃣ Install CLI\nargocd binary"]:::step
    D --> E["5️⃣ Create Ingress\nargocd.bit-habit.com"]:::step
    E --> F["6️⃣ Create Applications\nbit-habit-base + bit-habit-apps"]:::step
    F --> G["✅ Done!\nArgoCD is running"]:::done

    classDef step fill:#42A5F5,stroke:#1E88E5,color:#fff
    classDef done fill:#66BB6A,stroke:#43A047,color:#fff
```

---

## 6. Accessing the ArgoCD UI

### 6.1 Login credentials

| Field | Value |
|-------|-------|
| **URL** | `https://argocd.bit-habit.com` |
| **Username** | `admin` |
| **Password** | Run: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" \| base64 -d` |

> **Tip:** Change the admin password after first login:
> ```bash
> argocd account update-password
> ```

### 6.2 Opening the dashboard

Once you log in, you will see the **Applications** page. Each card represents one Application resource — a set of Kubernetes manifests that ArgoCD is managing.

```mermaid
flowchart LR
    subgraph dashboard["🖥️ ArgoCD Dashboard"]
        direction TB
        APP1["📦 bit-habit-base\n✅ Synced | 💚 Healthy"]:::synced
        APP2["📦 bit-habit-apps\n✅ Synced | 💚 Healthy"]:::synced
    end

    USER["👨‍💻 You"] -->|"https://argocd.bit-habit.com"| dashboard

    classDef synced fill:#4CAF50,stroke:#388E3C,color:#fff
```

Click on any application card to see:
- **Resource tree** — every Pod, Service, Deployment managed by this app
- **Sync status** — is the cluster matching Git?
- **Health** — are all Pods running?
- **Diff** — what changed since last sync?
- **History** — every sync that ever happened

---

## 7. Core concepts

### 7.1 Application

An **Application** is the main resource in ArgoCD. It tells ArgoCD:
- **Where** to get manifests (Git repo URL + path + branch)
- **Where** to deploy them (which cluster + namespace)
- **How** to sync (automatic or manual)

```mermaid
flowchart TD
    subgraph app["📋 Application Resource"]
        direction LR
        SRC["🔗 Source\nrepo: github.com/bookseal/bit-habit-infra\npath: apps/\nbranch: main"]:::source
        DST["🎯 Destination\nserver: kubernetes.default.svc\nnamespace: default"]:::dest
        POL["⚙️ Sync Policy\nauto-sync: enabled\nself-heal: true"]:::policy
    end

    SRC --> DST
    DST --> POL

    classDef source fill:#FF9800,stroke:#F57C00,color:#fff
    classDef dest fill:#2196F3,stroke:#1976D2,color:#fff
    classDef policy fill:#4CAF50,stroke:#388E3C,color:#fff
```

Our cluster has two Applications:

| Application | Watches | Contains |
|-------------|---------|----------|
| `bit-habit-base` | `base/` directory | Ingress, cert-manager, middlewares |
| `bit-habit-apps` | `apps/` directory | All app deployments and services |

### 7.2 Project

A **Project** groups Applications and controls what they can access. The `default` project allows everything. In a team environment, you would create separate projects to limit access.

```mermaid
flowchart TD
    subgraph proj["🗂️ Project: default"]
        A1["bit-habit-base"]:::app
        A2["bit-habit-apps"]:::app
    end

    proj -->|"Allowed repos"| R["github.com/bookseal/*"]:::rule
    proj -->|"Allowed clusters"| C["kubernetes.default.svc"]:::rule
    proj -->|"Allowed namespaces"| N["default, cert-manager, headlamp, ..."]:::rule

    classDef app fill:#42A5F5,stroke:#1E88E5,color:#fff
    classDef rule fill:#FFA726,stroke:#FB8C00,color:#fff
```

### 7.3 Sync and sync status

**Sync** means applying the Git manifests to the cluster.

| Status | Meaning | Color |
|--------|---------|-------|
| **Synced** | Cluster matches Git | 🟢 Green |
| **OutOfSync** | Cluster differs from Git | 🟡 Yellow |
| **Unknown** | ArgoCD cannot determine status | ⚪ Gray |

```mermaid
stateDiagram-v2
    direction LR

    [*] --> OutOfSync: App created
    OutOfSync --> Syncing: Sync triggered
    Syncing --> Synced: All resources applied
    Syncing --> OutOfSync: Sync failed
    Synced --> OutOfSync: Git changed or\ncluster drifted

    classDef synced fill:#4CAF50,color:#fff
    classDef outofsync fill:#FF9800,color:#fff
    classDef syncing fill:#2196F3,color:#fff
```

### 7.4 Health status

Health tells you if your applications are actually working (not just deployed).

| Status | Meaning | Color |
|--------|---------|-------|
| **Healthy** | All resources are running correctly | 💚 Green |
| **Progressing** | A rollout is in progress | 💙 Blue |
| **Degraded** | Something is failing | ❤️ Red |
| **Suspended** | Intentionally paused | ⏸️ Gray |
| **Missing** | Expected resource does not exist | ❓ Yellow |

```mermaid
flowchart TD
    DEPLOY["Deployment\nghost"]:::prog --> RS["ReplicaSet\nghost-abc123"]:::healthy
    RS --> P1["Pod ghost-abc123-x1\n✅ Running"]:::healthy
    RS --> P2["Pod ghost-abc123-x2\n❌ CrashLoopBackOff"]:::degraded

    DEPLOY -.->|"Health: Degraded 🔴"| STATUS["Overall: Degraded"]:::degraded

    classDef healthy fill:#4CAF50,stroke:#388E3C,color:#fff
    classDef degraded fill:#F44336,stroke:#D32F2F,color:#fff
    classDef prog fill:#2196F3,stroke:#1976D2,color:#fff
```

---

## 8. How our repo is connected

ArgoCD watches the `main` branch of this repository. Here is how the repo structure maps to ArgoCD Applications:

```mermaid
flowchart TD
    subgraph repo["📦 bookseal/bit-habit-infra (main branch)"]
        direction TB
        BASE["📁 base/\n├── ingress.yaml\n├── cert-manager/\n└── middlewares/"]:::base
        APPS["📁 apps/\n├── ghost/\n├── wikijs/\n├── bithabit-api/\n├── static-web/\n├── booktoss/\n├── code-server/\n├── headlamp/\n├── startpage/\n├── viz-platform/\n└── oauth2-proxy/"]:::apps
    end

    BASE -->|"Watched by"| A1["🔄 bit-habit-base\nApplication"]:::argo
    APPS -->|"Watched by"| A2["🔄 bit-habit-apps\nApplication"]:::argo

    A1 --> CLUSTER["☸️ k3s Cluster"]:::k8s
    A2 --> CLUSTER

    classDef base fill:#FF9800,stroke:#F57C00,color:#fff
    classDef apps fill:#9C27B0,stroke:#7B1FA2,color:#fff
    classDef argo fill:#2196F3,stroke:#1976D2,color:#fff
    classDef k8s fill:#4CAF50,stroke:#388E3C,color:#fff
```

---

## 9. Daily operations — how to use ArgoCD

### 9.1 Deploying a change

This is the new workflow. No more SSH + kubectl.

```mermaid
sequenceDiagram
    participant Dev as 👨‍💻 Developer
    participant Git as 📦 GitHub
    participant Argo as 🔄 ArgoCD
    participant K8s as ☸️ Cluster

    Dev->>Git: git push (edit deployment.yaml)
    Note over Git: Commit: "update ghost to v5.100"

    loop Every 3 minutes
        Argo->>Git: Poll for changes
    end

    Argo->>Git: Detects new commit
    Argo->>Argo: Compare Git vs Cluster
    Note over Argo: Status: OutOfSync

    alt Auto-sync enabled
        Argo->>K8s: kubectl apply (automatically)
        K8s-->>Argo: Resources updated
        Note over Argo: Status: Synced ✅
    else Manual sync
        Dev->>Argo: Click "Sync" in UI
        Argo->>K8s: kubectl apply
        K8s-->>Argo: Resources updated
        Note over Argo: Status: Synced ✅
    end
```

**Steps:**

1. Edit any YAML file in this repo (e.g., change the image tag in `apps/ghost/deployment.yaml`)
2. Commit and push to `main`
3. Wait ~3 minutes (ArgoCD polls every 3 minutes by default)
4. Check the ArgoCD dashboard — the app will show **OutOfSync** briefly, then **Synced**

> **Want instant sync?** After pushing, run:
> ```bash
> argocd app sync bit-habit-apps
> ```

### 9.2 Checking application status

**In the Web UI:**
- Go to `https://argocd.bit-habit.com`
- Each app card shows sync status and health at a glance

**From the CLI:**
```bash
# Overview of all apps
argocd app list

# Detailed status of one app
argocd app get bit-habit-apps
```

### 9.3 Manual sync

Sometimes you want to sync immediately without waiting for the poll interval.

**Web UI:** Click the app → click **SYNC** button → click **SYNCHRONIZE**.

**CLI:**
```bash
argocd app sync bit-habit-apps
```

```mermaid
flowchart LR
    A["🟡 OutOfSync"]:::oos --> B["🔄 Click SYNC"]:::action --> C["⏳ Syncing..."]:::syncing --> D["✅ Synced"]:::synced

    classDef oos fill:#FF9800,stroke:#F57C00,color:#fff
    classDef action fill:#2196F3,stroke:#1976D2,color:#fff
    classDef syncing fill:#FFC107,stroke:#FFA000,color:#000
    classDef synced fill:#4CAF50,stroke:#388E3C,color:#fff
```

### 9.4 Rolling back a deployment

Made a mistake? ArgoCD keeps a history of every sync.

**Web UI:** Click the app → **HISTORY AND ROLLBACK** → select the version you want → **Rollback**.

**CLI:**
```bash
# See sync history
argocd app history bit-habit-apps

# Rollback to a specific revision
argocd app rollback bit-habit-apps <HISTORY_ID>
```

```mermaid
flowchart TD
    subgraph history["📜 Sync History"]
        H1["v3 — current\nghost:5.100 ❌ broken"]:::bad
        H2["v2\nghost:5.99 ✅ worked"]:::good
        H1 --> H2
        H2 --> H3["v1\nghost:5.98"]:::old
    end

    H2 -->|"Rollback to v2"| RESULT["✅ Cluster restored\nghost:5.99 running"]:::good

    classDef bad fill:#F44336,stroke:#D32F2F,color:#fff
    classDef good fill:#4CAF50,stroke:#388E3C,color:#fff
    classDef old fill:#9E9E9E,stroke:#757575,color:#fff
```

> **Important:** After a rollback, ArgoCD will show **OutOfSync** because the cluster no longer matches Git. You should also revert the bad commit in Git to keep them aligned.

### 9.5 Force refresh

ArgoCD caches the Git repo state. If you just pushed and want ArgoCD to check immediately:

**Web UI:** Click **REFRESH** (top-right of the app page).

**CLI:**
```bash
argocd app get bit-habit-apps --refresh
```

---

## 10. Using the ArgoCD CLI

### 10.1 Login

```bash
# Login via the Kubernetes API (no need for port-forward)
argocd login argocd.bit-habit.com --grpc-web

# Or, from the server directly
argocd login localhost:8080 --insecure --username admin --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
```

### 10.2 List applications

```bash
argocd app list
```

Output:
```
NAME             CLUSTER                         NAMESPACE  STATUS   HEALTH   SYNCPOLICY
bit-habit-base   https://kubernetes.default.svc  default    Synced   Healthy  Auto(Self-Heal)
bit-habit-apps   https://kubernetes.default.svc  default    Synced   Healthy  Auto(Self-Heal)
```

### 10.3 Sync an application

```bash
# Sync one app
argocd app sync bit-habit-apps

# Sync all apps
argocd app sync --all
```

### 10.4 View application details

```bash
argocd app get bit-habit-apps
```

This shows:
- Every resource managed by the app
- Sync status of each resource
- Health of each resource
- Last sync time and result

### 10.5 View sync history

```bash
argocd app history bit-habit-apps
```

### 10.6 Rollback

```bash
# List history first
argocd app history bit-habit-apps

# Rollback to ID 2
argocd app rollback bit-habit-apps 2
```

---

## 11. The sync process — step by step

When ArgoCD syncs, here is exactly what happens:

```mermaid
flowchart TD
    A["1️⃣ Repo Server clones Git"]:::step --> B["2️⃣ Renders manifests\n(plain YAML, Helm, Kustomize)"]:::step
    B --> C["3️⃣ Controller compares\nGit manifests vs live state"]:::step
    C --> D{"4️⃣ Are they\nthe same?"}:::decision

    D -->|"Yes"| E["✅ Synced\nNo action needed"]:::synced
    D -->|"No"| F["5️⃣ Generate diff"]:::step
    F --> G["6️⃣ Apply changes\nkubectl apply"]:::step
    G --> H["7️⃣ Wait for health check"]:::step
    H --> I{"8️⃣ All healthy?"}:::decision
    I -->|"Yes"| J["✅ Sync successful"]:::synced
    I -->|"No"| K["⚠️ Sync succeeded\nbut health degraded"]:::warn

    classDef step fill:#42A5F5,stroke:#1E88E5,color:#fff
    classDef decision fill:#FFA726,stroke:#FB8C00,color:#fff
    classDef synced fill:#66BB6A,stroke:#43A047,color:#fff
    classDef warn fill:#FFF176,stroke:#FDD835,color:#000
```

| Phase | What happens |
|-------|-------------|
| **PreSync** | Run any pre-sync hooks (e.g., database migration Jobs) |
| **Sync** | Apply all manifests with `kubectl apply` |
| **PostSync** | Run any post-sync hooks (e.g., notification Jobs) |
| **SyncFail** | Run hooks designated for failure handling |

---

## 12. Self-heal and auto-prune

### Self-heal

When `selfHeal: true` is set (as in our config), ArgoCD automatically reverts manual changes.

```mermaid
flowchart LR
    subgraph normal["Normal State"]
        N1["Deployment\nreplicas: 2"]:::synced
    end

    subgraph manual["Someone runs:\nkubectl scale deploy ghost --replicas=1"]
        M1["Deployment\nreplicas: 1\n⚠️ Drifted!"]:::drift
    end

    subgraph healed["ArgoCD Self-Heal"]
        H1["Deployment\nreplicas: 2\n✅ Restored"]:::synced
    end

    normal --> manual -->|"~seconds"| healed

    classDef synced fill:#4CAF50,stroke:#388E3C,color:#fff
    classDef drift fill:#F44336,stroke:#D32F2F,color:#fff
```

**This means:** No one can break things by running random `kubectl` commands. Git is always the source of truth.

### Auto-prune

When `prune: true` is set, ArgoCD **deletes** resources that were removed from Git. We have `prune: false` as a safety measure — if you accidentally delete a YAML file from the repo, ArgoCD will NOT delete the running resource.

```mermaid
flowchart TD
    subgraph git_before["Git (before)"]
        G1["ghost/deployment.yaml ✅"]:::exists
        G2["ghost/service.yaml ✅"]:::exists
        G3["booktoss/deployment.yaml ✅"]:::exists
    end

    subgraph git_after["Git (after delete)"]
        G4["ghost/deployment.yaml ✅"]:::exists
        G5["ghost/service.yaml ✅"]:::exists
        G6["booktoss/deployment.yaml ❌ deleted"]:::deleted
    end

    subgraph prune_off["prune: false (our setting)"]
        P1["booktoss still running 🟡\nArgoCD shows: OutOfSync"]:::warn
    end

    subgraph prune_on["prune: true"]
        P2["booktoss deleted from cluster ⛔"]:::deleted
    end

    git_after --> prune_off
    git_after --> prune_on

    classDef exists fill:#4CAF50,stroke:#388E3C,color:#fff
    classDef deleted fill:#F44336,stroke:#D32F2F,color:#fff
    classDef warn fill:#FFC107,stroke:#FFA000,color:#000
```

---

## 13. Troubleshooting common issues

### Application stuck on "OutOfSync"

```bash
# Check what is different
argocd app diff bit-habit-apps

# Force a sync
argocd app sync bit-habit-apps --force
```

### Pod is in CrashLoopBackOff

ArgoCD will show the app as **Degraded**. This is a Kubernetes issue, not an ArgoCD issue.

```bash
# Check pod logs
kubectl logs <pod-name> -n <namespace>

# Check events
kubectl describe pod <pod-name> -n <namespace>
```

### ArgoCD cannot access the Git repo

```bash
# Check repo connection
argocd repo list

# Test connectivity
argocd repo add https://github.com/bookseal/bit-habit-infra.git --username <user> --password <token>
```

### Sync fails with "resource already exists"

This happens when a resource was created outside of ArgoCD. Fix:

```bash
# Tell ArgoCD to adopt the existing resource
kubectl annotate <resource-type> <resource-name> argocd.argoproj.io/managed-by=bit-habit-apps
```

```mermaid
flowchart TD
    PROBLEM["🔴 Problem"]:::problem --> CHECK{"What is wrong?"}:::decision

    CHECK -->|"OutOfSync"| FIX1["Run: argocd app diff\nthen: argocd app sync --force"]:::fix
    CHECK -->|"Degraded"| FIX2["Check: kubectl logs\nand: kubectl describe pod"]:::fix
    CHECK -->|"Repo error"| FIX3["Check: argocd repo list\nRe-add if needed"]:::fix
    CHECK -->|"Already exists"| FIX4["Annotate resource\nwith ArgoCD label"]:::fix

    classDef problem fill:#F44336,stroke:#D32F2F,color:#fff
    classDef decision fill:#FF9800,stroke:#F57C00,color:#fff
    classDef fix fill:#4CAF50,stroke:#388E3C,color:#fff
```

---

## 14. Security best practices

1. **Change the admin password** after first login
   ```bash
   argocd account update-password
   ```

2. **Delete the initial admin secret** once the password is changed
   ```bash
   kubectl -n argocd delete secret argocd-initial-admin-secret
   ```

3. **Use HTTPS** for Git repo access (not SSH) when possible — easier to manage

4. **Use RBAC** to limit who can sync or delete applications
   ```yaml
   # In argocd-rbac-cm ConfigMap
   policy.csv: |
     p, role:readonly, applications, get, */*, allow
     p, role:readonly, applications, sync, */*, deny
   ```

5. **Set up SSO** instead of the built-in admin account (ArgoCD supports GitHub, Google, OIDC)

```mermaid
flowchart TD
    subgraph security["🔒 Security Checklist"]
        S1["✅ Change admin password"]:::done
        S2["✅ Delete initial secret"]:::done
        S3["✅ Use HTTPS for repos"]:::done
        S4["⬜ Set up RBAC policies"]:::todo
        S5["⬜ Enable SSO"]:::todo
        S6["✅ TLS via Traefik"]:::done
    end

    classDef done fill:#4CAF50,stroke:#388E3C,color:#fff
    classDef todo fill:#9E9E9E,stroke:#757575,color:#fff
```

---

## 15. Quick reference cheat sheet

| Task | Command |
|------|---------|
| Login | `argocd login argocd.bit-habit.com --grpc-web` |
| List apps | `argocd app list` |
| Sync app | `argocd app sync bit-habit-apps` |
| Sync all | `argocd app sync --all` |
| App details | `argocd app get bit-habit-apps` |
| App diff | `argocd app diff bit-habit-apps` |
| Sync history | `argocd app history bit-habit-apps` |
| Rollback | `argocd app rollback bit-habit-apps <ID>` |
| Force refresh | `argocd app get bit-habit-apps --refresh` |
| Hard refresh | `argocd app get bit-habit-apps --hard-refresh` |
| Delete app | `argocd app delete bit-habit-apps` |
| List repos | `argocd repo list` |
| Get password | `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" \| base64 -d` |
| ArgoCD pods | `kubectl get pods -n argocd` |
| ArgoCD logs | `kubectl logs -n argocd deployment/argocd-server` |

```mermaid
flowchart LR
    subgraph workflow["🔄 Daily GitOps Workflow"]
        direction LR
        W1["Edit YAML"]:::step --> W2["git commit"]:::step --> W3["git push"]:::step --> W4["ArgoCD syncs"]:::step --> W5["Check dashboard"]:::step
    end

    classDef step fill:#42A5F5,stroke:#1E88E5,color:#fff
```

---

> **Next steps:** Once you are comfortable with ArgoCD basics, explore:
> - **ApplicationSets** — generate applications from templates (e.g., one per directory in `apps/`)
> - **Notifications** — get Slack/email alerts when syncs happen
> - **Image Updater** — automatically update image tags when new versions are pushed to a registry
> - **SSO with GitHub** — use your GitHub account instead of the admin password
