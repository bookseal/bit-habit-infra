#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${NAMESPACE:-kubernetes-dashboard}"
SECRET_NAME="${SECRET_NAME:-oauth2-proxy-secret}"

if [[ -z "${OAUTH2_PROXY_COOKIE_SECRET:-}" ]]; then
  echo "OAUTH2_PROXY_COOKIE_SECRET is required" >&2
  exit 1
fi

if [[ -z "${OAUTH2_PROXY_CLIENT_ID:-}" ]]; then
  echo "OAUTH2_PROXY_CLIENT_ID is required" >&2
  exit 1
fi

if [[ -z "${OAUTH2_PROXY_CLIENT_SECRET:-}" ]]; then
  echo "OAUTH2_PROXY_CLIENT_SECRET is required" >&2
  exit 1
fi

kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
  --from-literal=cookie-secret="${OAUTH2_PROXY_COOKIE_SECRET}" \
  --from-literal=client-id="${OAUTH2_PROXY_CLIENT_ID}" \
  --from-literal=client-secret="${OAUTH2_PROXY_CLIENT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deploy/oauth2-proxy -n "${NAMESPACE}"
kubectl rollout status deploy/oauth2-proxy -n "${NAMESPACE}"
