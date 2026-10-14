# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

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
