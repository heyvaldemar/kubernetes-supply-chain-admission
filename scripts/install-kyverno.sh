#!/usr/bin/env bash
# install-kyverno.sh - Kyverno into the current cluster, from the chart
# version pinned below, with every image pinned by digest (kyverno/images.yaml).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART_VERSION=3.9.1
helm upgrade --install kyverno kyverno --repo https://kyverno.github.io/kyverno/ --version "$CHART_VERSION" \
  --namespace kyverno --create-namespace --wait --timeout 10m \
  -f "$ROOT/kyverno/images.yaml" -f "$ROOT/kyverno/values.yaml"
kubectl -n kyverno rollout status deployment/kyverno-admission-controller --timeout=300s
