# bit-habit-infra

This repository now documents the full picture in **two layers**:

1. `k3s-bootstrap/`
   The server-side bootstrap layer for k3s itself
2. `base/` and `apps/`
   The cluster workload layer for ingress, certificates, apps, and admin UI

That split is the easiest way to understand how this cluster is actually managed.

## 1. Start Here: Two Layers, Two Responsibilities

If you are confused about "where k3s ends" and "where app manifests begin", this is the boundary:

```mermaid
flowchart TD
    Server["Server / OS"]
    Bootstrap["k3s-bootstrap/"]
    K3s["k3s control plane and node services"]
    System["Traefik, kube-system, cert-manager"]
    Workloads["base/ and apps/"]
    Public["Public domains and admin UI"]

    Server --> Bootstrap --> K3s --> System --> Workloads --> Public
```

Read it like this:

- `k3s-bootstrap/` is for how the cluster itself is installed and configured.
- `base/` and `apps/` are for what runs inside that cluster.
- This repo now keeps both ideas visible, but they are still different layers.

## 2. Beginner-First Reading and Deployment Order

If you only want the shortest path to understanding this repo, read and apply in this order:

```mermaid
flowchart TD
    A["1. Read k3s-bootstrap/README.md"]
    B["2. Understand k3s-bootstrap/config.yaml.example"]
    C["3. Apply base/cert-manager"]
    D["4. Apply base/middlewares and base/ingress"]
    E["5. Apply public apps from apps/"]
    F["6. Apply apps/headlamp/deployment.yaml"]
    G["7. Create oauth2-proxy-secret in headlamp"]
    H["8. Apply apps/oauth2-proxy"]
    I["9. Open domains and verify"]

    A --> B --> C --> D --> E --> F --> G --> H --> I
```

Typical workload commands:

```bash
kubectl apply -f base/cert-manager/
kubectl apply -f base/middlewares/
kubectl apply -f base/ingress.yaml

kubectl apply -f apps/static-web/deployment.yaml
kubectl apply -f apps/startpage/deployment.yaml
kubectl apply -f apps/booktoss/deployment.yaml
kubectl apply -f apps/ghost/deployment.yaml
kubectl apply -f apps/wikijs/deployment.yaml

kubectl apply -f apps/headlamp/deployment.yaml

kubectl create secret generic oauth2-proxy-secret \
  -n headlamp \
  --from-literal=cookie-secret="YOUR_COOKIE_SECRET" \
  --from-literal=client-id="YOUR_GITHUB_CLIENT_ID" \
  --from-literal=client-secret="YOUR_GITHUB_CLIENT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f apps/oauth2-proxy/deployment.yaml
kubectl apply -f apps/oauth2-proxy/ingress.yaml
```

## 3. What `k3s-bootstrap/` Means

`k3s-bootstrap/` is the place for the part that was previously missing from this repo:

- how the k3s server is installed
- how `/etc/rancher/k3s/config.yaml` is managed
- how `/etc/rancher/k3s/registries.yaml` is managed
- how operators think about the generated kubeconfig at `/etc/rancher/k3s/k3s.yaml`

This directory is **not** auto-applied by Kubernetes. It is a documentation and template layer for the server itself.

```mermaid
flowchart LR
    Repo["k3s-bootstrap/*"]
    Host["Server filesystem"]
    Config["/etc/rancher/k3s/config.yaml"]
    Registries["/etc/rancher/k3s/registries.yaml"]
    Kubeconfig["/etc/rancher/k3s/k3s.yaml"]
    Service["systemd k3s service"]

    Repo --> Host
    Host --> Config
    Host --> Registries
    Service --> Kubeconfig
```

## 4. Public Admin Entry Screen

This is the public landing screen currently shown at `https://k8s.bit-habit.com` before GitHub authentication. The screenshot was captured on **March 18, 2026 (UTC)**.

![Public login screen for k8s.bit-habit.com](assets/k8s-bit-habit-com-login.png)

Operational meaning:

- the public URL is fronted by `oauth2-proxy`
- unauthenticated users see GitHub sign-in first
- `Headlamp` only appears after successful GitHub OAuth

## 5. The One-Sentence Model

This repo manages the cluster in two stages:

- `k3s-bootstrap/` explains how the k3s host is configured
- `base/` and `apps/` run `Route53 -> Traefik -> Ingress -> Service -> Pod` workloads inside that cluster

## 6. Three Files You Should Read First

If you are new, these are the three files I would read first.

### 6.1 [`k3s-bootstrap/config.yaml.example`](k3s-bootstrap/config.yaml.example)

Why this file matters:

- it tells you how the k3s server itself is started
- it is the line between "server setup" and "Kubernetes manifests"
- if this part is wrong, everything above it becomes confusing

Example content:

```yaml
write-kubeconfig-mode: "0644"
disable:
  - servicelb
tls-san:
  - k8s.bit-habit.com
node-label:
  - "bit-habit.com/role=main"
```

Beginner explanation:

- `write-kubeconfig-mode` controls who can read the generated kubeconfig.
- `disable` turns off bundled components you do not want. Here it disables `servicelb`.
- `tls-san` adds extra names to the API server certificate.
- `node-label` gives the node a stable identity you can later target from Kubernetes.

### 6.2 [`base/ingress.yaml`](base/ingress.yaml)

Why this file matters:

- this is the public front door for most domains
- it explains how traffic becomes a Service call
- if you want to know "what host points to what app", this is the first workload file to inspect

Example content:

```yaml
metadata:
  name: main-ingress
  namespace: default
  annotations:
    kubernetes.io/ingress.class: traefik
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - bit-habit.com
    - "*.bit-habit.com"
    secretName: tls-secret
```

Beginner explanation:

- this says Traefik should handle the ingress
- it enables HTTPS entry through `websecure`
- it asks cert-manager to use `letsencrypt-prod`
- it declares that `tls-secret` should terminate TLS for the root domain and wildcard subdomains

### 6.3 [`apps/headlamp/deployment.yaml`](apps/headlamp/deployment.yaml)

Why this file matters:

- it shows how the admin UI lives inside the cluster
- it shows the `ServiceAccount` and `ClusterRoleBinding` relationship
- it makes the difference between GitHub login and Kubernetes permissions very concrete

Example content:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: headlamp-admin
  namespace: headlamp
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: headlamp-admin
roleRef:
  kind: ClusterRole
  name: cluster-admin
```

Beginner explanation:

- GitHub login controls who reaches the UI.
- This file controls what the UI can do after login.
- Here, `headlamp-admin` is bound to `cluster-admin`, so the UI has very broad access.

## 7. Public Traffic Flow

Read public traffic before you read the admin UI.

```mermaid
flowchart LR
    User["Browser"]
    R53["Route53 DNS"]
    Node["k3s node public IP"]
    Traefik["Traefik ingress controller"]
    Ingress["Ingress rules"]
    Service["ClusterIP Service"]
    Pod["Deployment / Pod"]
    Data["hostPath or in-cluster DB"]

    Issuer["ClusterIssuer"]
    Cert["Certificate"]
    CM["cert-manager"]
    TLS["tls-secret"]

    User --> R53 --> Node --> Traefik --> Ingress --> Service --> Pod --> Data

    Issuer --> CM
    Cert --> CM
    CM -->|DNS-01 challenge| R53
    CM --> TLS --> Traefik
```

Four things to remember:

1. `Route53` resolves domains and participates in DNS-01 validation.
2. `Traefik` is the public ingress controller.
3. `Ingress` maps hostnames and paths to `Service` objects.
4. `Service` sends traffic to the actual application Pods.

## 8. File Inventory by Layer

### 8.1 `k3s-bootstrap/`

| File | Purpose | Beginner note |
| --- | --- | --- |
| `k3s-bootstrap/README.md` | Explains what belongs to the k3s server layer | Start here if you want the "whole picture" |
| `k3s-bootstrap/config.yaml.example` | Example k3s server config | Maps to `/etc/rancher/k3s/config.yaml` |
| `k3s-bootstrap/registries.yaml.example` | Example private registry / mirror config | Maps to `/etc/rancher/k3s/registries.yaml` |
| `k3s-bootstrap/install-server.sh.example` | Example installation command for the first server | Shows how bootstrap and config tie together |

### 8.2 `base/`

`base/` is the cluster front door: certificates, shared ingress, and shared Traefik middleware.

| File | What it defines | Beginner note |
| --- | --- | --- |
| `base/cert-manager/cluster-issuer.yaml` | Production `ClusterIssuer` using Let’s Encrypt and `Route53` DNS-01 | Defines how certificates are issued |
| `base/cert-manager/aws-secret.yaml` | `route53-credentials-secret` | Gives cert-manager access to Route53 |
| `base/cert-manager/certificate.yaml` | Wildcard certificate request for `bit-habit.com` and `*.bit-habit.com` | Produces `tls-secret` |
| `base/ingress.yaml` | Main public ingress plus `/api/` ingress for `habit.bit-habit.com` | Most domain routing starts here |
| `base/middlewares/strip-api-middleware.yaml` | Traefik `Middleware` that strips `/api` | Makes API paths line up with backend expectations |

### 8.3 `apps/`

`apps/` holds the actual workloads, admin components, and operator helper files.

| File | What it defines | Beginner note |
| --- | --- | --- |
| `apps/static-web/deployment.yaml` | `static-web` Deployment and Service | Serves `bit-habit.com`, `habit.bit-habit.com`, and `status.bit-habit.com` |
| `apps/startpage/deployment.yaml` | `startpage` Deployment and Service | Serves `startpage.bit-habit.com` |
| `apps/booktoss/deployment.yaml` | `booktoss` Deployment and Service | Depends on `booktoss-env` |
| `apps/code-server/deployment.yaml` | `code-server` Deployment and Service | Browser-based development environment |
| `apps/viz-platform/deployment.yaml` | `viz-platform` Deployment and Service | Source tree mounted from the node |
| `apps/bithabit-api/deployment.yaml` | `bithabit-api` Deployment and Service | API running inside the cluster |
| `apps/bithabit-api/service.yaml` | `bithabit-api-svc` Service and manual `Endpoints` | Alternative API mode forwarding to `10.0.0.61:8002` |
| `apps/ghost/deployment.yaml` | `ghost-mysql` and `ghost` Deployments plus Services | Blog plus MySQL |
| `apps/wikijs/deployment.yaml` | `wikijs-db` and `wikijs` Deployments plus Services | Wiki.js plus PostgreSQL |
| `apps/headlamp/README.md` | Headlamp notes | Headlamp-specific operator guidance |
| `apps/headlamp/deployment.yaml` | Headlamp namespace, RBAC, Deployment, and Service | Admin UI runtime |
| `apps/oauth2-proxy/README.md` | oauth2-proxy notes | GitHub OAuth setup and troubleshooting |
| `apps/oauth2-proxy/deployment.yaml` | oauth2-proxy Deployment and Service | Admin authentication layer |
| `apps/oauth2-proxy/ingress.yaml` | Traefik `IngressRoute` for `k8s.bit-habit.com` | Public admin entrypoint |
| `apps/oauth2-proxy/secret.example.yaml.disabled` | Example Secret template | Helper template only |
| `apps/oauth2-proxy/update-secret.sh` | Secret rotation helper | Updates the GitHub OAuth Secret and restarts oauth2-proxy |

### 8.4 `assets/`

| File | Purpose | Beginner note |
| --- | --- | --- |
| `assets/k8s-bit-habit-com-login.png` | Public screenshot of the admin entry page | Shows what users see before GitHub authentication |

## 9. Where the Layers Meet

This is the most useful mental model in the whole repo:

```mermaid
flowchart LR
    Bootstrap["k3s-bootstrap"]
    Cluster["k3s cluster"]
    Base["base/"]
    Apps["apps/"]
    Users["public users and operators"]

    Bootstrap --> Cluster --> Base --> Apps --> Users
```

`k3s-bootstrap/` prepares the cluster.  
`base/` opens the front door.  
`apps/` provides the workloads.

## 10. Current Domain Map

| Host | Path | Target | Source file |
| --- | --- | --- | --- |
| `bit-habit.com` | `/` | `static-web-svc` | `base/ingress.yaml` |
| `www.bit-habit.com` | `/` | `static-web-svc` | `base/ingress.yaml` |
| `blog.bit-habit.com` | `/` | `ghost-svc` | `base/ingress.yaml` |
| `www.blog.bit-habit.com` | `/` | `ghost-svc` | `base/ingress.yaml` |
| `booktoss.bit-habit.com` | `/` | `booktoss-svc` | `base/ingress.yaml` |
| `code-server.bit-habit.com` | `/` | `code-server-svc` | `base/ingress.yaml` |
| `daily-seongsu.bit-habit.com` | `/` | `daily-seongsu-svc` | `base/ingress.yaml` |
| `habit.bit-habit.com` | `/` | `static-web-svc` | `base/ingress.yaml` |
| `habit.bit-habit.com` | `/api/` | `bithabit-api-svc` plus `/api` stripping | `base/ingress.yaml`, `base/middlewares/strip-api-middleware.yaml` |
| `startpage.bit-habit.com` | `/` | `startpage-svc` | `base/ingress.yaml` |
| `status.bit-habit.com` | `/` | `static-web-svc` | `base/ingress.yaml` |
| `seoul-apt.bit-habit.com` | `/` | `seoul-apt-price` | `base/ingress.yaml` |
| `viz.bit-habit.com` | `/` | `viz-platform-svc` | `base/ingress.yaml` |
| `wiki.bit-habit.com` | `/` | `wikijs-svc` | `base/ingress.yaml` |
| `www.wiki.bit-habit.com` | `/` | `wikijs-svc` | `base/ingress.yaml` |
| `k8s.bit-habit.com` | `/` | `oauth2-proxy -> Headlamp` | `apps/oauth2-proxy/ingress.yaml` |

Two Services are referenced in ingress but do not currently have matching manifests in `apps/`:

- `daily-seongsu-svc`
- `seoul-apt-price`

That usually means they are managed elsewhere or are still missing from this repo.

## 11. How Route53 and cert-manager Issue TLS

This repo uses `AWS Route53`. cert-manager creates the DNS-01 challenge records in Route53, waits for validation, and then stores the certificate in `tls-secret`.

```mermaid
sequenceDiagram
    participant Cert as certificate.yaml
    participant Issuer as cluster-issuer.yaml
    participant CM as cert-manager
    participant AWS as Route53
    participant Secret as tls-secret
    participant Ingress as Traefik Ingress

    Cert->>CM: Request wildcard certificate
    Issuer->>CM: Use Let's Encrypt plus Route53
    CM->>AWS: Create DNS-01 TXT record
    AWS-->>CM: Challenge becomes visible
    CM-->>Secret: Store issued certificate in tls-secret
    Secret-->>Ingress: HTTPS termination uses tls-secret
```

## 12. Admin UI Flow

`k8s.bit-habit.com` does not point directly to Headlamp. It first goes through `oauth2-proxy`, and only authenticated users reach Headlamp.

```mermaid
sequenceDiagram
    participant U as User
    participant R as Route53
    participant T as Traefik IngressRoute
    participant O as oauth2-proxy
    participant G as GitHub OAuth
    participant H as Headlamp
    participant K as Kubernetes API

    U->>R: Resolve k8s.bit-habit.com
    U->>T: Open admin URL
    T->>O: Forward request
    O->>G: Redirect to GitHub login
    G-->>O: OAuth callback
    O->>H: Proxy authenticated request
    H->>K: Read cluster state with ServiceAccount
    K-->>H: Return cluster resources
    H-->>U: Render the admin UI
```

Key distinction:

- GitHub OAuth controls who can reach the UI.
- Kubernetes RBAC controls what that UI can do once inside.

## 13. Can Headlamp Provide a Shell or kubectl Access?

In practical terms:

- Headlamp can inspect resources, show logs, and open pod-level exec sessions.
- Headlamp is still not a full browser shell environment in this repo.
- This repo does not currently provide a general-purpose web terminal or raw `kubectl` shell from the browser.

If you want that later, the sensible options are:

- Headlamp Desktop with a local kubeconfig on an operator machine
- a separate web terminal behind `oauth2-proxy` with tight RBAC and audit controls

## 14. Verification

General checks:

```bash
kubectl get ns
kubectl get pods -A
kubectl get ingress -A
kubectl get ingressroute -A
```

Headlamp and oauth2-proxy checks:

```bash
kubectl get pods -n headlamp
kubectl logs deploy/headlamp -n headlamp --tail=100
kubectl logs deploy/oauth2-proxy -n headlamp --tail=100
```

Server-side k3s checks:

```bash
sudo cat /etc/rancher/k3s/config.yaml
sudo cat /etc/rancher/k3s/registries.yaml
sudo cat /etc/rancher/k3s/k3s.yaml
sudo systemctl status k3s
```

## 15. Beginner Gotchas

### A `Service` is not the application itself

The real containers are in `Deployment -> Pod`. A `Service` is the stable network front for them.

### `Ingress` is only the front door

`Ingress` decides where traffic goes. It does not run the application code.

### `hostPath` couples workloads to one node

If you move a workload to another node without the same files and directories, it can break.

### `bithabit-api` has two different operating modes

- `apps/bithabit-api/deployment.yaml` runs the API inside the cluster.
- `apps/bithabit-api/service.yaml` forwards to an external IP `10.0.0.61:8002`.

They both touch `bithabit-api-svc`, so do not apply both casually.

### `k3s-bootstrap/` is not a Kubernetes apply directory

Those files describe the host-side k3s setup. They are templates and notes, not cluster manifests.

## 16. One-Line Memory Aid

The easiest way to understand this repo is:

`k3s-bootstrap/` creates the cluster, `base/` opens the front door, and `apps/` runs what users and operators actually touch.
