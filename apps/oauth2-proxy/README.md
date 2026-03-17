# OAuth2 Proxy for Headlamp

GitHub SSO authentication for `k8s.bit-habit.com`

## Prerequisites

1. Create GitHub OAuth App at https://github.com/settings/developers
   - Application name: `k8s-dashboard`
   - Homepage URL: `https://k8s.bit-habit.com`
   - Callback URL: `https://k8s.bit-habit.com/oauth2/callback`

2. Get Client ID and Client Secret

## Installation

```bash
# 1. Generate cookie secret
COOKIE_SECRET=$(openssl rand -base64 32 | head -c 32)

# 2. Create secret with actual values
kubectl create secret generic oauth2-proxy-secret \
  -n kubernetes-dashboard \
  --from-literal=cookie-secret="$COOKIE_SECRET" \
  --from-literal=client-id="YOUR_GITHUB_CLIENT_ID" \
  --from-literal=client-secret="YOUR_GITHUB_CLIENT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Apply OAuth2 Proxy
kubectl apply -f deployment.yaml
kubectl apply -f ingress.yaml

# 4. Restart and inspect logs
kubectl rollout restart deploy/oauth2-proxy -n kubernetes-dashboard
kubectl rollout status deploy/oauth2-proxy -n kubernetes-dashboard
kubectl logs deploy/oauth2-proxy -n kubernetes-dashboard --tail=100
```

`deployment.yaml` does not include the Secret on purpose. This prevents
`kubectl apply -f apps/ --recursive` from replacing the real GitHub OAuth
credentials with placeholder values.

If you prefer YAML instead of `kubectl create secret`, use
`secret.example.yaml.disabled` as the starting point and keep the filename
outside recursive apply patterns until the real values are filled in.

To rotate the GitHub OAuth credentials safely, use `update-secret.sh`:

```bash
export OAUTH2_PROXY_COOKIE_SECRET='your-cookie-secret'
export OAUTH2_PROXY_CLIENT_ID='your-client-id'
export OAUTH2_PROXY_CLIENT_SECRET='your-client-secret'
./update-secret.sh
```

You can override the namespace with `NAMESPACE=... ./update-secret.sh`.

## Access

1. Go to https://k8s.bit-habit.com
2. Click "Sign in with GitHub"
3. Authorize the app
4. Headlamp loads automatically

This setup protects the public Headlamp URL with GitHub login.
Headlamp itself uses the in-cluster `headlamp-admin` service account.

## Allowed Users

By default, GitHub-authenticated users are allowed through.
Add `--github-user=your-username` in `deployment.yaml` to allow a specific user only.
Or use `--github-org=your-org` to allow organization members.

If the authenticated GitHub account does not match the allowed user or org,
OAuth succeeds but the callback ends with `403 Forbidden`.

## Quick Verification

1. Open `https://k8s.bit-habit.com/oauth2/start`
2. Sign in with GitHub
3. Confirm the browser lands on `https://k8s.bit-habit.com/`
4. If it fails, inspect `kubectl logs deploy/oauth2-proxy -n kubernetes-dashboard --tail=100`
