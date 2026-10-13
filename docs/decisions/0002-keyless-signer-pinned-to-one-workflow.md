# 2. Keyless signatures, pinned to one workflow

- Status: accepted
- Date: 2026-10-13

## Context

A signature proves who signed only if the verifier knows who to expect. A long-lived signing key has to live somewhere the build can reach and nothing else can. A rule that accepts any signature from an account accepts every workflow that account will ever run.

## Decision

Images are signed with cosign keyless: the publish workflow exchanges its GitHub OIDC token for a short-lived certificate from Sigstore's Fulcio, and the signature is recorded in Rekor. The policy accepts exactly one identity: `.github/workflows/publish.yml` of this repository, on `refs/heads/main`, issued by GitHub Actions. The static check fails on a pattern or a regular expression in its place.

## Consequences

- There is no key to leak; the identity is the workflow file on `main`.
- Renaming the publish workflow or signing from another branch is a policy change, reviewed as one.
- Verification depends on Sigstore's public infrastructure being reachable at admission; a private Sigstore deployment or a key-based signature removes that dependency at the cost of managing a key.

## Alternatives

- **A key pair in a KMS.** No public infrastructure on the admission path; a key to protect and an identity that is "whoever can use the key".
- **Any workflow of the account (`subjectRegExp`).** Convenient for many repositories; every workflow of the account becomes a signer, including one added next year.

## How to explain this to a customer

Only our own build pipeline, running from our reviewed main branch, can produce software the cluster accepts. There is no signing key to steal: the pipeline proves who it is each time it builds.
