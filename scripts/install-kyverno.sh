#!/usr/bin/env bash
# install-kyverno.sh - Kyverno into the current cluster, from the chart
# version pinned below, with every image pinned by digest (kyverno/images.yaml).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART_VERSION=3.9.2
helm upgrade --install kyverno kyverno --repo https://kyverno.github.io/kyverno/ --version "$CHART_VERSION" \
  --namespace kyverno --create-namespace --wait --timeout 10m \
  -f "$ROOT/kyverno/images.yaml" -f "$ROOT/kyverno/values.yaml"
kubectl -n kyverno rollout status deployment/kyverno-admission-controller --timeout=300s

# Rolled out is not serving. On a fresh CI cluster on 2026-10-13 the webhook
# that validates policies refused connections right after the rollout, and
# applying the image policy failed. Ready means a server-side dry run of that
# policy goes through.
for _ in $(seq 1 60); do
  kubectl apply --dry-run=server -f "$ROOT/policies/verify-images.yaml" >/dev/null 2>&1 && exit 0
  sleep 5
done
echo "Kyverno's webhook did not answer within five minutes:" >&2
kubectl apply --dry-run=server -f "$ROOT/policies/verify-images.yaml"
exit 1
