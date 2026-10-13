# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

_(no unreleased changes yet)_

## [1.0.0] - 2026-10-13

### Added

- A publish workflow that builds three demo images, signs two of them keyless with its own GitHub identity, and attaches signed SLSA v1 provenance, a CycloneDX SBOM and a Trivy scan to each, re-scanned daily.
- A Kyverno ImageValidatingPolicy that admits an image only with that signer, provenance naming this repository, an SBOM, and a scan that read an operating system's packages and found nothing critical.
- A native ValidatingAdmissionPolicy registry allowlist that holds while Kyverno is down.
- The kind e2e suite, including what is admitted with Kyverno at zero, and the static checks, each shown its planted violation.
- A threat model with three findings from the build, and four decision records.

[Unreleased]: https://github.com/heyvaldemar/kubernetes-supply-chain-admission/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/kubernetes-supply-chain-admission/releases/tag/v1.0.0
