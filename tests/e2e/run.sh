#!/usr/bin/env bash
# tests/e2e/run.sh - prove what the README says against the kind cluster in
# the current kubeconfig (Kyverno installed, policies and namespace applied),
# with the images the publish workflow pushed last.
#
#   1-4. each manifest in tests/e2e/plants, with the digests the registry
#      holds today filled in: the signed image (provenance, SBOM, a clean
#      scan) admitted and running; the unsigned image, the one with a
#      critical vulnerability, a reference by tag and an image signed by
#      someone else each refused, for the reason the plant names
#   5. the image signed by someone else, refused by Kyverno alone too
#   6. with Kyverno's admission controller at zero, the unsigned image from
#      this registry is admitted (the gap docs/threat-model.md names) and an
#      image from anywhere else is still refused; with Kyverno back, the
#      unsigned image is refused again
#
# Needs kubectl, docker (for `docker buildx imagetools`) and python3.
# shellcheck disable=SC2015
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=ghcr.io/heyvaldemar/kubernetes-supply-chain-admission
WORK="$(mktemp -d)"
# Signed by Sigstore's own release workflow: a real signature, the wrong signer.
OTHER=ghcr.io/sigstore/cosign/cosign:v3.1.3@sha256:9e5c2f2edc34351160407ca3416c61855bdf9403c3c5936e0f0be7fc261611b8
results=()
failed=0

pass() { results+=("PASS  $1"); printf '  ok    %s\n' "$1"; }
fail() { results+=("FAIL  $1"); printf '  FAIL  %s\n' "$1"; failed=1; }
note() { results+=("NOTE  $1"); printf '  note  %s\n' "$1"; }
step() { printf '\n== %s\n' "$*"; }

# shellcheck disable=SC2329  # called by the EXIT trap
cleanup() {
  kubectl -n kyverno scale deployment kyverno-admission-controller --replicas=1 >/dev/null 2>&1
  kubectl apply -f "$HERE/../../policies/registry-allowlist.yaml" >/dev/null 2>&1
  kubectl -n workloads delete pod signed --ignore-not-found --wait=false >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

digest_of() { docker buildx imagetools inspect "$1" 2>/dev/null | awk '/^Digest:/{print $2}'; }
pod() {  # pod <name> <image>: a pod that meets Pod Security restricted
  cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $1
  namespace: workloads
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: $2
      resources:
        requests: {cpu: 10m, memory: 16Mi}
        limits: {memory: 32Mi}
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: [ALL]
EOF
}
try() {  # try <name> <image>: the API server's answer to a server-side dry run
  pod "$1" "$2" | kubectl apply --dry-run=server -f - 2>&1
}
# apply_once_more <label> <outfile> <kubectl apply args...>
# A webhook that times out has made no decision: the API server refuses the
# request, and a pod's controller would create it again. The run does the
# same, once, and records it as a NOTE in the summary, so a slow registry
# shows up as a trend and not as a refusal the policy never made. Not called
# from a command substitution: note() has to reach this shell's results.
apply_once_more() {
  local label="$1" outfile="$2"; shift 2
  kubectl apply "$@" >"$outfile" 2>&1 && return 0
  grep -q 'failed calling webhook' "$outfile" && grep -q 'context deadline exceeded' "$outfile" || return 1
  note "$label: the admission webhook timed out without a decision; applied once more, as a controller would"
  kubectl apply "$@" >"$outfile" 2>&1
}
refused_for() {  # refused_for <label> <name> <image> <reason>
  local out
  pod "$2" "$3" >"$WORK/$2.pod.yaml"
  apply_once_more "$1" "$WORK/$2.out" --dry-run=server -f "$WORK/$2.pod.yaml"
  out="$(cat "$WORK/$2.out")"
  if grep -qF -- "$4" <<<"$out"; then pass "$1: refused ($4)"; else fail "$1: expected a refusal saying '$4', got: ${out:0:300}"; fi
}

APP="$REPO/app@$(digest_of "$REPO/app:latest")"
UNSIGNED="$REPO/unsigned@$(digest_of "$REPO/unsigned:latest")"
VULNERABLE="$REPO/vulnerable@$(digest_of "$REPO/vulnerable:latest")"
for ref in "$APP" "$UNSIGNED" "$VULNERABLE"; do
  [[ "$ref" == *@sha256:* ]] || { echo "could not resolve $ref; has the publish workflow run?" >&2; exit 1; }
done

# --- 1-4 ---------------------------------------------------------------------
step "1-4. the plants, with today's digests"
for plant in "$HERE"/plants/*.yaml; do
  name="$(basename "$plant" .yaml)"
  expect="$(sed -n 's/^# expect: //p' "$plant")"
  sed -e "s#IMAGE_APP#$APP#" -e "s#IMAGE_UNSIGNED#$UNSIGNED#" -e "s#IMAGE_VULNERABLE#$VULNERABLE#" "$plant" >"$WORK/$name.yaml"
  if [ "$expect" = admitted ]; then
    if apply_once_more "$name" "$WORK/$name.err" -f "$WORK/$name.yaml" &&
       kubectl -n workloads wait --for=condition=Ready "pod/$name" --timeout=180s >/dev/null 2>&1; then
      pass "$name: admitted and running"
    else
      fail "$name was not admitted or did not run: $(cat "$WORK/$name.err")"
    fi
  else
    apply_once_more "$name" "$WORK/$name.out" --dry-run=server -f "$WORK/$name.yaml"
    out="$(cat "$WORK/$name.out")"
    grep -qF -- "$expect" <<<"$out" && pass "$name: refused ($expect)" \
      || fail "$name: expected a refusal saying '$expect', got: ${out:0:300}"
  fi
done

# --- 5 -----------------------------------------------------------------------
step "5. signed by someone else, with Kyverno alone"
kubectl delete validatingadmissionpolicybinding registry-allowlist >/dev/null
sleep 3
refused_for "another signer, Kyverno alone" other "$OTHER" "every image is signed by this repository's publish workflow on main"
kubectl apply -f "$HERE/../../policies/registry-allowlist.yaml" >/dev/null
sleep 3

# --- 6 -----------------------------------------------------------------------
step "6. Kyverno down"
kubectl -n kyverno scale deployment kyverno-admission-controller --replicas=0 >/dev/null
kubectl -n kyverno wait --for=delete pod -l app.kubernetes.io/component=admission-controller --timeout=180s >/dev/null 2>&1
sleep 5
if try unsigned "$UNSIGNED" | grep -q "created (server dry run)"; then
  pass "with Kyverno at zero, the unsigned image from this registry is admitted: signature checks need a running webhook"
else
  fail "with Kyverno at zero, the unsigned image was refused; the threat model's gap has changed: $(try unsigned "$UNSIGNED" | head -1)"
fi
refused_for "another registry, Kyverno down" other "$OTHER" "images come from ghcr.io/heyvaldemar/kubernetes-supply-chain-admission/"
kubectl -n kyverno scale deployment kyverno-admission-controller --replicas=1 >/dev/null
kubectl -n kyverno rollout status deployment/kyverno-admission-controller --timeout=300s >/dev/null
back=""
for _ in $(seq 1 30); do
  back="$(try unsigned "$UNSIGNED")"
  grep -q "publish workflow on main" <<<"$back" && break
  sleep 5
done
grep -q "publish workflow on main" <<<"$back" && pass "with Kyverno back, the unsigned image is refused again" \
  || fail "with Kyverno back, the unsigned image is not refused: ${back:0:300}"

# A copy the status workflow reads (scripts/status.py), when one is asked for.
if [ -n "${E2E_RESULTS:-}" ]; then
  { printf 'R\t%s\n' "${results[@]}"; } | python3 -c '
import json, sys
checks, measured = [], []
for line in sys.stdin:
    kind, _, text = line.rstrip("\n").partition("\t")
    if kind == "R" and text:
        state, _, name = text.partition("  ")
        checks.append({"state": state.strip(), "name": name.strip()})
    elif kind == "M" and text:
        measured.append(text)
json.dump({"checks": checks, "measured": measured}, sys.stdout)
' >"$E2E_RESULTS"
fi

# --- summary -----------------------------------------------------------------
printf '\n'
printf '%s\n' "${results[@]}"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### supply chain admission e2e"; echo; echo '```'; printf '%s\n' "${results[@]}"; echo '```'; } >>"$GITHUB_STEP_SUMMARY"
fi
exit "$failed"
