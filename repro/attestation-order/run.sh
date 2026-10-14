#!/usr/bin/env bash
# run.sh IMAGE@DIGEST - one image, the same two signed attestations of one
# type, two orders of the registry's referrers index, and Kyverno's answer to
# each. Reproduced when the answers differ: the policy reads whichever
# attestation the index lists last, not the newer one.
#
# Needs a cluster with Kyverno (scripts/install-kyverno.sh), kubectl, python3,
# GITHUB_REPOSITORY (owner/name, whose workflow signed the attestations), and
# REGISTRY_USER and REGISTRY_TOKEN that can push to the image's repository.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
image="${1:?usage: run.sh IMAGE@DIGEST}"
repo="${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY to owner/name}"

sed -e "s#REPOSITORY_LC#${repo,,}#g" -e "s#REPOSITORY#$repo#g" "$HERE/policy.yaml" | kubectl apply -f - >/dev/null
kubectl create namespace attestation-order --dry-run=client -o yaml \
  | kubectl label --local -f - attestation-order=repro -o yaml | kubectl apply -f - >/dev/null
kubectl wait --for=jsonpath='{.status.conditionStatus.ready}'=true imagevalidatingpolicy/attestation-order --timeout=120s >/dev/null

# The API server's answer to a pod with the image, by server-side dry run.
# A webhook that timed out or was not up yet has not decided; ask again.
answer() {
  local out
  for _ in 1 2 3 4 5 6; do
    out="$(kubectl -n attestation-order run probe --image="$image" --restart=Never --dry-run=server 2>&1)" \
      && { echo "admitted"; return; }
    grep -qE 'context deadline exceeded|connection refused|no endpoints available' <<<"$out" || break
    sleep 10
  done
  if grep -qF 'extractPayload() returned the older attestation' <<<"$out"; then
    echo 'refused: extractPayload() returned the older attestation, the one that says "first"'
  else
    echo "refused for another reason: ${out:0:300}"
  fi
}

declare -A got
for order in newest-last newest-first; do
  python3 "$HERE/order.py" "$order" "$image"
  # Kyverno caches verification results; a fresh admission controller asks
  # the registry again and sees the new order.
  kubectl -n kyverno rollout restart deployment/kyverno-admission-controller >/dev/null
  kubectl -n kyverno rollout status deployment/kyverno-admission-controller --timeout=300s >/dev/null
  got[$order]="$(answer)"
  echo "  Kyverno: ${got[$order]}"
done

echo
if [ "${got[newest-last]}" = admitted ] && [[ "${got[newest-first]}" == refused:* ]]; then
  echo "REPRODUCED: the same two signed attestations, in two index orders, got two answers."
  echo "With the newer one listed last the pod is admitted; listed first, extractPayload() returns the older one."
  exit 0
fi
echo "NOT REPRODUCED: newest-last ${got[newest-last]}; newest-first ${got[newest-first]}"
exit 1
