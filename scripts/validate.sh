#!/usr/bin/env bash
# validate.sh [check...] - the static checks, without a cluster:
#
#   kubeconform   the namespace, the registry allowlist and every plant are
#                 valid Kubernetes 1.37 objects
#   images        every image this repository builds on or runs is by digest
#                 (the plants are excluded: one of them is a tag on purpose)
#   policy        the image policy pins one exact signer, denies, fails closed,
#                 and requires a digest and all four checks
#
# With no arguments every check runs. tests/static/plants.tsv shows each
# check the violation it exists for (tests/static/plant_violations.py).
# The check_* functions are called by name from the loop at the bottom.
# shellcheck disable=SC2329
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

KUBE_VERSION=1.37.0
# yannh/kubernetes-json-schema at a fixed commit. K8S_SCHEMAS may point at a
# local checkout of the same commit instead.
default_schemas='https://raw.githubusercontent.com/yannh/kubernetes-json-schema/817113f21a2643311cbc3e992bb44ffe1c416c54/{{.NormalizedKubernetesVersion}}-standalone{{.StrictSuffix}}/{{.ResourceKind}}{{.KindSuffix}}.json'
K8S_SCHEMAS="${K8S_SCHEMAS:-$default_schemas}"

check_kubeconform() {
  mkdir -p .cache/kubeconform
  kubeconform -strict -summary -output text -kubernetes-version "$KUBE_VERSION" \
    -cache .cache/kubeconform -schema-location "$K8S_SCHEMAS" \
    manifests policies/registry-allowlist.yaml tests/e2e/plants
}

check_images() {
  local bad
  bad="$( { grep -rnE '^FROM ' images | grep -v '@sha256:';
            grep -rnE '(_IMAGE: |^OTHER=)' .github/workflows tests/e2e/run.sh | grep -v '@sha256:'; } || true)"
  if [ -n "$bad" ]; then echo "images without a digest:"; echo "$bad"; return 1; fi
  echo "every image is referenced by digest"
}

check_policy() {
  python3 - policies/verify-images.yaml <<'PY'
import sys, yaml
p = yaml.safe_load(open(sys.argv[1]))
spec, bad = p["spec"], []
ids = [i for a in spec.get("attestors", []) for i in a.get("cosign", {}).get("keyless", {}).get("identities", [])]
if not ids:
    bad.append("no keyless identity: anyone's signature would do")
for i in ids:
    if "subjectRegExp" in i or "*" in i.get("subject", "*"):
        bad.append(f"signer {i} is a pattern, not one workflow")
    if i.get("issuer") != "https://token.actions.githubusercontent.com":
        bad.append(f"signer {i} is not issued by GitHub Actions")
if spec.get("validationActions") != ["Deny"]:
    bad.append(f"validationActions is {spec.get('validationActions')}, not [Deny]")
if spec.get("failurePolicy") != "Fail":
    bad.append("failurePolicy is not Fail: a verification that cannot run would admit")
cfg = spec.get("validationConfigurations", {})
if not cfg.get("verifyDigest") or not cfg.get("required"):
    bad.append("a digest and a verification are not both required")
if [m.get("glob") for m in spec.get("matchImageReferences", [])] != ["*"]:
    bad.append("not every image is matched; one from elsewhere would skip verification")
text = " ".join(v["expression"] for v in spec.get("validations", []))
for name in ("attestors.publisher", "attestations.provenance", "attestations.sbom", "attestations.scan"):
    if name not in text:
        bad.append(f"no validation uses {name}")
for b in bad:
    print("policy: " + b)
print("the image policy pins one signer, denies, fails closed" if not bad else f"{len(bad)} problem(s)")
sys.exit(1 if bad else 0)
PY
}

checks=("$@")
[ ${#checks[@]} -eq 0 ] && checks=(kubeconform images policy)
failed=0
for c in "${checks[@]}"; do
  if "check_$c"; then echo "-- $c: ok"; else echo "-- $c: FAILED"; failed=1; fi
done
exit "$failed"
