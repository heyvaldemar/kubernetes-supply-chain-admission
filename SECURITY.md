# Security policy

## Supported versions

| Version | Supported |
|---|---|
| The latest release | yes |
| `main` | yes |
| Older releases | no |

## Reporting a vulnerability

Report privately through GitHub: **Security → Report a vulnerability** on this repository. Email to v@valdemar.ai also works. The process is described at [heyvaldemar.com/security](https://heyvaldemar.com/security/).

You can expect an acknowledgment within 7 days. There is no bounty program; valid, responsibly disclosed reports are credited in the changelog. Please do not open public issues for security reports.

## What this repository is

A reference, not a hosted service. A vulnerability here is most likely an image that gets admitted without what the README says it needs: a signature from the publish workflow, provenance, an SBOM, a clean scan.

## Supply chain

- Container images are pinned by digest, and CI fails on one that is not.
- The demo images are signed keyless by the publish workflow on `main`, with signed provenance, an SBOM and a vulnerability scan attached; `cosign verify` and `cosign verify-attestation` check them from anywhere (README).

## Credentials

None stored. The publish workflow signs with a short-lived certificate issued to its own GitHub identity, so no signing key exists, and it pushes with the workflow's own `GITHUB_TOKEN`.
