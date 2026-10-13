#!/usr/bin/env bash
# verify-published.sh - check the published images the way anyone can,
# without a cluster: cosign against the registry and Sigstore's public
# instance, with the one identity the policy accepts.
#
#   app        signed, with provenance, an SBOM and a scan attached
#   unsigned   no signature from that identity
#
# Needs cosign. Run by the e2e workflow next to the cluster checks.
set -uo pipefail

REPO=ghcr.io/heyvaldemar/kubernetes-supply-chain-admission
IDENTITY=https://github.com/heyvaldemar/kubernetes-supply-chain-admission/.github/workflows/publish.yml@refs/heads/main
ISSUER=https://token.actions.githubusercontent.com
failed=0

ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; failed=1; }

if cosign verify "$REPO/app:latest" --certificate-identity "$IDENTITY" --certificate-oidc-issuer "$ISSUER" >/dev/null 2>&1; then
  ok "app: signed by the publish workflow on main"
else
  bad "app: no signature from the publish workflow on main"
fi
for type in slsaprovenance1 cyclonedx vuln; do
  if cosign verify-attestation --type "$type" "$REPO/app:latest" \
       --certificate-identity "$IDENTITY" --certificate-oidc-issuer "$ISSUER" >/dev/null 2>&1; then
    ok "app: signed $type attestation"
  else
    bad "app: no signed $type attestation"
  fi
done
if cosign verify "$REPO/unsigned:latest" --certificate-identity "$IDENTITY" --certificate-oidc-issuer "$ISSUER" >/dev/null 2>&1; then
  bad "unsigned: verified, and it must not be"
else
  ok "unsigned: no signature from the publish workflow"
fi
exit "$failed"
