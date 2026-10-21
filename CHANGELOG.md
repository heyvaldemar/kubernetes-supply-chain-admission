# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Security

- With Kyverno's admission controller at zero, an unsigned image from this repository's own registry path was admitted: Kyverno removes its webhook configurations as it goes down, and the registry allowlist cannot check a signature. The e2e run measured it on purpose and the threat model listed it. `policies/kyverno-guard.yaml` (ADR 5) is a ValidatingAdmissionPolicy whose parameter is Kyverno's own webhook configuration, `parameterNotFoundAction: Deny`: while the webhook for `verify-images` is missing, the API server refuses every pod in the verified namespace. The e2e run's step 6 now requires the unsigned image, the signed image and one from another registry refused with Kyverno at zero; CI waits for the webhook before any pod; static check `policy` holds the guard, two plants. The same guard as the air-gapped agent's ADR 17.

### Fixed

- `make up` on macOS: its make (3.81) ran a simple recipe without a shell, so the `PATH` the Makefile exports never reached it and `kind` was not found. Every recipe now runs in bash.
- Attestations no longer pile up on the published images. The images build to the same digest, and every daily publish run added four Sigstore bundles to it; Kyverno verifies each one on every admission, so the work grew by four bundles a day with no limit. It was found while chasing e2e runs that failed on the webhook's timeout, which it did not cause alone: with four bundles an admission still took 4 to 26 seconds. With two scans attached, which one the policy read depended on the order of GHCR's referrers index ([kyverno/kyverno#18000](https://github.com/kyverno/kyverno/issues/18000) reports the same for `verifyImages`). The publish run now keeps the newest bundle of each kind (`scripts/referrers.py prune`), Verify runs the selection rule on planted data, and the e2e run fails if a published image carries two bundles of a kind.

### Changed

- The status workflow hands its push credential to git through git's environment, not its command line, which any process on the runner can read.
- helm v4.3.1 in `tools.lock`, its hashes checked against helm's own checksum files.
- The webhook waits 30 seconds, the API server's maximum, instead of 25: one verified admission took 4 to 26 seconds in the e2e runs. When the webhook still times out without a decision, the e2e run applies once more, as a pod's controller would, and records it as a NOTE in its summary; a refusal is never retried.
- The attestor has no `ctlog` block. The transparency log is still required, but Kyverno checks each bundle's inclusion proof offline against Rekor's key from Sigstore's TUF root instead of calling Rekor at every admission. Rekor is off the admission path. Admission is not measurably faster: 4 to 17 seconds across eight e2e runs without the online client, inside the 7 to 26 seconds seen with it.
- The threat model, ADR 1 and the policy's comment no longer call Kyverno's `extractPayload()` example wrong. It reads `.bomFormat` at the top level for a Notary referrer, whose payload is the SBOM itself, and is right for that; a cosign in-toto attestation returns the whole statement, so its content is under `.predicate`. The documentation shows one of the two kinds.
- The threat model links the two reports made upstream from its findings: [kyverno/website#2201](https://github.com/kyverno/website/pull/2201), a note on the in-toto payload, and [aquasecurity/trivy discussion 11403](https://github.com/aquasecurity/trivy/discussions/11403), on the exit status of a scan that found no operating system packages.

### Added

- Three e2e plants, `no-provenance`, `no-sbom` and `no-scan`: a signed image missing each attestation, refused for the one it lacks. `scripts/verify-published.sh` checks each is signed and lacks exactly that attestation. The README's claims table, the threat model and the Cyber Resilience Act mapping now cite these refusals; the mapping no longer lists the gap.
- Three more published images, `no-provenance`, `no-sbom` and `no-scan`, from `images/partial`: signed by the publish workflow like `app`, each with one attestation left off, so the e2e can show the policy refusing each missing attestation on its own.
- `docs/cyber-resilience-act.md`: each control mapped to the clause of the Cyber Resilience Act (Regulation (EU) 2024/2847) it produces evidence for, quoted from the Official Journal text, with what each leaves out. Writing it found a gap the README does not claim to close: no e2e plant shows an image signed without an SBOM, or without provenance, being refused.
- `AGENTS.md` (and a `CLAUDE.md` that imports it): the rules an AI agent working on this repository is held to: claims only as CI checks, a check trusted only after it has failed, risky changes proved on a branch and image changes on main after the publish run, where each pin lives, numbers read from runs, how a release is cut and verified, and what is never done (a weakened policy, a retried refusal, a second attestation of one type, a publish run from a branch).
- A weekly check of every pin against upstream: `scripts/check-freshness.py`, run by the verify workflow on its schedule and by hand. It compares the charts the scripts install with their repository's index, every image pinned by digest with what its tag resolves to now, the tools in `tools.lock` with their newest releases, and the CI images. Dependabot here watched the workflows' actions and nothing else, so a chart, an image or a tool could fall behind without a sound. Its first run found helm one patch behind.
- Live status: every e2e run uploads its checks and measurements (`E2E_RESULTS`), and `.github/workflows/status.yml` rewrites the `status` branch after each run with the last 30 days on main: green days, the streak, the latest checks (`scripts/status.py`). The README's second row of badges reads it.
- A recording of the e2e run (`docs/demo/e2e.cast`, rendered to `docs/demo/e2e.gif`), in the README.
- `repro/attestation-order`: a reproduction, started by hand, of Kyverno's `ImageValidatingPolicy` returning whichever of several attestations of one type the referrers index lists last ([kyverno/kyverno#18000](https://github.com/kyverno/kyverno/issues/18000)). One image, the same two signed attestations, two index orders, and the answer the API server gives for each: admitted with the newer listed last, refused with it listed first, in both runs so far. Reported as [kyverno/kyverno#18023](https://github.com/kyverno/kyverno/issues/18023).
- CodeQL (security-extended) on the Python and the workflows, on every push and weekly.
- The OpenSSF Best Practices badge, passing, and a README section on where a bug, a question or a change goes.

## [1.0.0] - 2026-10-13

### Added

- A publish workflow that builds three demo images, signs two of them keyless with its own GitHub identity, and attaches signed SLSA v1 provenance, a CycloneDX SBOM and a Trivy scan to each, re-scanned daily.
- A Kyverno ImageValidatingPolicy that admits an image only with that signer, provenance naming this repository, an SBOM, and a scan that read an operating system's packages and found nothing critical.
- A native ValidatingAdmissionPolicy registry allowlist that holds while Kyverno is down.
- The kind e2e suite, including what is admitted with Kyverno at zero, and the static checks, each shown its planted violation.
- A threat model with three findings from the build, and four decision records.

[Unreleased]: https://github.com/heyvaldemar/kubernetes-supply-chain-admission/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/kubernetes-supply-chain-admission/releases/tag/v1.0.0
