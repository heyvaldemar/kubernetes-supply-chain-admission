#!/usr/bin/env bash
# tests/e2e/run.sh - prove what the README says against the kind cluster in
# the current kubeconfig (Kyverno installed, policies and namespace applied),
# with the images the publish workflow pushed last.
#
#   1-4. each manifest in tests/e2e/plants, with the digests the registry
#      holds today filled in: the signed image (provenance, SBOM, a clean
#      scan) admitted and running; the unsigned image, the one with a
#      critical vulnerability, a reference by tag, an image signed by
#      someone else, and three signed images that each lack one attestation
#      (provenance, SBOM, scan) each refused, for the reason the plant names;
#      and beside the signed image, an init container nobody signed, an
#      image nobody signed mounted as a volume, and a volume from another
#      registry, each refused: every image a pod uses meets the same bar
#   5. the image signed by someone else, refused by Kyverno alone too
#   6. with Kyverno's admission controller at zero, the unsigned image, the
#      signed image and one from another registry are each refused (ADR 5's
#      guard: an outage, not a hole), and so is an ephemeral container added
#      to the running pod; with Kyverno back, the unsigned image is refused
#      for its signature again
#   7. an ephemeral container added to the running signed pod, the way
#      `kubectl debug` adds one, through the pod's ephemeralcontainers
#      subresource: the signed image admitted (the control), one nobody
#      signed and one from another registry refused
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
# What `kubectl debug` sends: the running pod with one more ephemeral
# container, to its ephemeralcontainers subresource, as a dry run. A policy
# that matches pods alone never sees this request.
ephemeral() {  # ephemeral <image>: the API server's answer
  kubectl -n workloads get pod signed -o json | python3 -c '
import json, sys
pod = json.load(sys.stdin)
pod["spec"].setdefault("ephemeralContainers", []).append({
    "name": "debug", "image": sys.argv[1], "command": ["sleep", "60"],
    "securityContext": {"allowPrivilegeEscalation": False, "readOnlyRootFilesystem": True,
                        "runAsNonRoot": True, "capabilities": {"drop": ["ALL"]}}})
print(json.dumps(pod))' "$1" | kubectl replace --raw "/api/v1/namespaces/workloads/pods/signed/ephemeralcontainers?dryRun=All" -f - 2>&1
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
NO_PROVENANCE="$REPO/no-provenance@$(digest_of "$REPO/no-provenance:latest")"
NO_SBOM="$REPO/no-sbom@$(digest_of "$REPO/no-sbom:latest")"
NO_SCAN="$REPO/no-scan@$(digest_of "$REPO/no-scan:latest")"
for ref in "$APP" "$UNSIGNED" "$VULNERABLE" "$NO_PROVENANCE" "$NO_SBOM" "$NO_SCAN"; do
  [[ "$ref" == *@sha256:* ]] || { echo "could not resolve $ref; has the publish workflow run?" >&2; exit 1; }
done

# --- 1-4 ---------------------------------------------------------------------
step "1-4. the plants, with today's digests"
for plant in "$HERE"/plants/*.yaml; do
  name="$(basename "$plant" .yaml)"
  expect="$(sed -n 's/^# expect: //p' "$plant")"
  sed -e "s#IMAGE_APP#$APP#" -e "s#IMAGE_UNSIGNED#$UNSIGNED#" -e "s#IMAGE_VULNERABLE#$VULNERABLE#" \
    -e "s#IMAGE_NO_PROVENANCE#$NO_PROVENANCE#" -e "s#IMAGE_NO_SBOM#$NO_SBOM#" -e "s#IMAGE_NO_SCAN#$NO_SCAN#" \
    -e "s#IMAGE_OTHER#$OTHER#" \
    "$plant" >"$WORK/$name.yaml"
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
# Kyverno removes its webhook configurations as it goes down only once it has
# seen its own Deployment at zero, which it does not always have by then.
# Wait up to half a minute for them to go, so the case the guard (ADR 5)
# exists for is the one tested, and say which it was.
for _ in $(seq 1 15); do
  kubectl get validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg >/dev/null 2>&1 || break
  sleep 2
done
if kubectl get validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg >/dev/null 2>&1; then
  note "Kyverno kept its webhook configuration this time: the API server refuses by failing to call it"
else
  note "Kyverno removed its webhook configuration as it went down: only the API server's guard is left to refuse"
fi
down() {  # down <label> <name> <image>: refused, for whatever reason the API server gives
  local out; out="$(try "$2" "$3")"
  if grep -q "created (server dry run)" <<<"$out"; then fail "$1: admitted"
  else pass "$1: refused ($(sed -E 's/.*denied request: //; s/.*(failed calling webhook)/\1/' <<<"$out" | head -1 | cut -c1-120))"; fi
}
down "with Kyverno at zero, the unsigned image from this registry" unsigned "$UNSIGNED"
down "with Kyverno at zero, the signed image too, an outage and not a hole" app "$APP"
down "with Kyverno at zero, an image from another registry" other "$OTHER"
if out="$(ephemeral "$APP")"; then fail "with Kyverno at zero, an ephemeral container with the signed image: admitted"
else pass "with Kyverno at zero, an ephemeral container is refused too, the signed image included ($(sed -E 's/.*denied request: //' <<<"$out" | head -1 | cut -c1-120))"; fi
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

# --- 7 -----------------------------------------------------------------------
step "7. an ephemeral container in the running signed pod"
if out="$(ephemeral "$APP")"; then pass "control: an ephemeral container with the signed image is admitted"
else fail "control: an ephemeral container with the signed image was refused, so the refusals below prove nothing: ${out:0:300}"; fi
for case in "unsigned|$UNSIGNED|every image is signed by this repository's publish workflow on main" \
            "from another registry|$OTHER|images come from ghcr.io/heyvaldemar/kubernetes-supply-chain-admission/, by digest"; do
  IFS='|' read -r what image expect <<<"$case"
  if out="$(ephemeral "$image")"; then fail "an ephemeral container $what: admitted"
  elif grep -qF -- "$expect" <<<"$out"; then pass "an ephemeral container $what: refused ($expect)"
  else fail "an ephemeral container $what: expected a refusal saying '$expect', got: ${out:0:300}"; fi
done

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
