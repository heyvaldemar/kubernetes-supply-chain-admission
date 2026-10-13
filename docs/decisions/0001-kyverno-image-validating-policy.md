# 1. Kyverno's ImageValidatingPolicy for verification at admission

- Status: accepted
- Date: 2026-10-13

## Context

Image signatures and attestations are only worth what checks them. The check has to run when a pod is created, read signatures and in-toto attestations from the registry, verify them against Sigstore, and evaluate what the attestations say.

## Decision

Kyverno 1.19's ImageValidatingPolicy (`policies/verify-images.yaml`): cosign keyless attestors, in-toto attestations declared by predicate type, and CEL over the verified payloads (`verifyImageSignatures`, `verifyAttestationSignatures`, `extractPayload`). The same engine the companion platform runs for its other policies, from the same pinned chart.

## Consequences

- One policy carries the signer, the provenance source, the SBOM and the scan rule, with a message per rule that says which one failed.
- It is a webhook. When Kyverno is down, it does not run; the native registry allowlist (ADR 4) is the floor.
- `extractPayload()` returns the in-toto statement, so payload fields are under `.predicate`; the threat model records how that surfaced.

## Alternatives

- **Sigstore policy-controller.** Purpose-built for Sigstore verification, with CUE or Rego over attestations. A second admission engine next to Kyverno for clusters that already run Kyverno.
- **Ratify with Gatekeeper.** Strong for Notation and OCI referrers, verification as an external data provider. Another two components, and its natural fit is Notary signatures rather than cosign keyless.
- **Verification in CI only.** A pipeline that checks before it deploys is bypassed by anything that does not go through it: a `kubectl apply`, another pipeline, a compromised one.

## How to explain this to a customer

The cluster itself checks every piece of software before it starts it, at the moment it is asked to run it, so nothing can skip the check by arriving through a different door.
