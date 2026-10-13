# 3. Provenance, an SBOM, and a scan that read something

- Status: accepted
- Date: 2026-10-13

## Context

A signature says who built an image. It does not say from what, what is inside, or whether any of it is known to be exploitable today.

## Decision

The publish workflow attaches three signed attestations to every image it signs, and the policy requires all three:

- SLSA v1 provenance whose resolved source is this repository, generated and signed in the build job;
- a CycloneDX SBOM from Syft;
- a vulnerability scan from Trivy in the cosign-vuln format, which must contain an operating system's packages and no critical finding.

The scan is re-run and re-attested daily on a schedule.

## Consequences

- An image with a critical vulnerability is refused even though it is signed and has provenance; the e2e run proves it with one.
- A scan that read nothing is refused instead of counted as clean. Building on a base the scanner recognises is part of the contract.
- The provenance is Build L2: written by the job that builds. An isolated generator would be L3 and is the upgrade path.
- Older scans stay attached to the image; see the threat model.

## Alternatives

- **Scan at admission time.** Always current, and slow and network-heavy on the admission path; a scan result signed by the pipeline is cheaper to check.
- **SBOM only, no scan gate.** Inventory without a decision; it tells you what is inside and leaves the question of whether it may run to a person.

## How to explain this to a customer

Each piece of software comes with a signed record of where it was built, a list of what is inside it, and a security scan from within the last day. Anything with a known critical weakness is stopped before it starts, even if our own pipeline built it.
