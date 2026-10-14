# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- Attestations no longer pile up on the published images. The images build to the same digest, and every daily publish run added four Sigstore bundles to it; Kyverno verifies each one on every admission, so the work grew by four bundles a day with no limit. It was found while chasing e2e runs that failed on the webhook's timeout, which it did not cause alone: with four bundles an admission still took 4 to 26 seconds. With two scans attached, which one the policy read depended on the order of GHCR's referrers index ([kyverno/kyverno#18000](https://github.com/kyverno/kyverno/issues/18000) reports the same for `verifyImages`). The publish run now keeps the newest bundle of each kind (`scripts/referrers.py prune`), Verify runs the selection rule on planted data, and the e2e run fails if a published image carries two bundles of a kind.

### Changed

- The webhook waits 30 seconds, the API server's maximum, instead of 25: one verified admission took 4 to 26 seconds in the e2e runs. When the webhook still times out without a decision, the e2e run applies once more, as a pod's controller would, and records it as a NOTE in its summary; a refusal is never retried.
- The attestor has no `ctlog` block. The transparency log is still required, but Kyverno checks each bundle's inclusion proof offline against Rekor's key from Sigstore's TUF root instead of calling Rekor at every admission. Rekor is off the admission path. Admission is not measurably faster: 4 to 17 seconds across eight e2e runs without the online client, inside the 7 to 26 seconds seen with it.

### Added

- `repro/attestation-order`: a reproduction, started by hand, of Kyverno's `ImageValidatingPolicy` returning whichever of several attestations of one type the referrers index lists last ([kyverno/kyverno#18000](https://github.com/kyverno/kyverno/issues/18000)). One image, the same two signed attestations, two index orders, and the answer the API server gives for each.
- CodeQL (security-extended) on the Python and the workflows, on every push and weekly.
- The OpenSSF Best Practices badge, passing, and a README section on where a bug, a question or a change goes.

### Changed

- The threat model, ADR 1 and the policy's comment no longer call Kyverno's `extractPayload()` example wrong. It reads `.bomFormat` at the top level for a Notary referrer, whose payload is the SBOM itself, and is right for that; a cosign in-toto attestation returns the whole statement, so its content is under `.predicate`. The documentation shows one of the two kinds.
- The threat model links the two reports made upstream from its findings: [kyverno/website#2201](https://github.com/kyverno/website/pull/2201), a note on the in-toto payload, and [aquasecurity/trivy discussion 11403](https://github.com/aquasecurity/trivy/discussions/11403), on the exit status of a scan that found no operating system packages.

## [1.0.0] - 2026-10-13

### Added

- A publish workflow that builds three demo images, signs two of them keyless with its own GitHub identity, and attaches signed SLSA v1 provenance, a CycloneDX SBOM and a Trivy scan to each, re-scanned daily.
- A Kyverno ImageValidatingPolicy that admits an image only with that signer, provenance naming this repository, an SBOM, and a scan that read an operating system's packages and found nothing critical.
- A native ValidatingAdmissionPolicy registry allowlist that holds while Kyverno is down.
- The kind e2e suite, including what is admitted with Kyverno at zero, and the static checks, each shown its planted violation.
- A threat model with three findings from the build, and four decision records.

[Unreleased]: https://github.com/heyvaldemar/kubernetes-supply-chain-admission/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/kubernetes-supply-chain-admission/releases/tag/v1.0.0
