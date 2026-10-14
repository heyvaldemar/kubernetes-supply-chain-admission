# kubernetes-supply-chain-admission

[![Supply chain e2e](https://github.com/heyvaldemar/kubernetes-supply-chain-admission/actions/workflows/e2e.yml/badge.svg)](https://github.com/heyvaldemar/kubernetes-supply-chain-admission/actions/workflows/e2e.yml)
[![Publish](https://github.com/heyvaldemar/kubernetes-supply-chain-admission/actions/workflows/publish.yml/badge.svg)](https://github.com/heyvaldemar/kubernetes-supply-chain-admission/actions/workflows/publish.yml)
[![Verify](https://github.com/heyvaldemar/kubernetes-supply-chain-admission/actions/workflows/verify.yml/badge.svg)](https://github.com/heyvaldemar/kubernetes-supply-chain-admission/actions/workflows/verify.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/heyvaldemar/kubernetes-supply-chain-admission/badge)](https://scorecard.dev/viewer/?uri=github.com/heyvaldemar/kubernetes-supply-chain-admission)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15464/badge)](https://www.bestpractices.dev/projects/15464)

A digest pins bytes. It does not say who built them, from what, or what is inside. This repository makes a Kubernetes cluster ask before it runs an image: a signature from one known build, signed provenance that names the source, an SBOM, and a scan from the last day that read the image and found nothing critical. Kyverno checks all four at admission, and a native policy holds the registry line when Kyverno is down.

It is a reference, not a product, and it does not run in production anywhere. It runs on kind at no cloud cost. The images are not mocks: this repository's own workflow builds and signs them every day.

## What is proven, and how

Every line is a check in `tests/e2e/run.sh` on a fresh cluster, or in `scripts/validate.sh`. The refusals are paired with a signed image that must be admitted and run, so no check can pass because the cluster refuses everything.

| Claim | Proof |
|---|---|
| An image with a signature, provenance, an SBOM and a clean scan runs | the signed demo image, by its digest from the registry today, admitted and running |
| An image the build did not sign is refused | the unsigned image, pushed by the same workflow, refused for its signature |
| A signed image with a critical vulnerability is refused | the signed and attested image whose scan found CVE-2021-36159 refused for its scan |
| An image signed by someone else is refused | an image signed by Sigstore's own release workflow, refused by Kyverno alone for its signer and by the native policy for its registry |
| A verified image cannot be swapped under its tag | the signed image referenced by tag refused |
| The policy reads one scan per image, the newest | the publish run keeps one bundle of each kind on each signed image, and the e2e run reads the registry and fails on two of a kind; the selection rule is run on planted data in Verify |
| What still holds when Kyverno is down is measured | with Kyverno at zero, the unsigned image from this registry is admitted (the gap, on purpose) and an image from anywhere else is still refused; with Kyverno back, the unsigned image is refused again |
| Every static check can fail | a base image by tag, a misspelled field in the allowlist binding, a signer pattern that trusts a whole account and a policy that admits when it cannot verify, each planted and each caught |

## What the run reports

From a run against the images published today:

```text
PASS  by-tag: refused (images come from ghcr.io/heyvaldemar/kubernetes-supply-chain-admission/, by digest)
PASS  other-signer: refused (images come from ghcr.io/heyvaldemar/kubernetes-supply-chain-admission/)
PASS  signed: admitted and running
PASS  unsigned: refused (every image is signed by this repository's publish workflow on main)
PASS  vulnerable: refused (a signed scan that read its operating system's packages and found nothing critical)
PASS  another signer, Kyverno alone: refused (every image is signed by this repository's publish workflow on main)
PASS  with Kyverno at zero, the unsigned image from this registry is admitted: signature checks need a running webhook
PASS  another registry, Kyverno down: refused (images come from ghcr.io/heyvaldemar/kubernetes-supply-chain-admission/)
PASS  with Kyverno back, the unsigned image is refused again
```

Anyone can check the same images without a cluster; `scripts/verify-published.sh` runs these checks, and the three attestation types, in every e2e run:

```bash
cosign verify ghcr.io/heyvaldemar/kubernetes-supply-chain-admission/app:latest \
  --certificate-identity https://github.com/heyvaldemar/kubernetes-supply-chain-admission/.github/workflows/publish.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
cosign verify-attestation --type slsaprovenance1 ghcr.io/heyvaldemar/kubernetes-supply-chain-admission/app:latest \
  --certificate-identity https://github.com/heyvaldemar/kubernetes-supply-chain-admission/.github/workflows/publish.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## How it works

```mermaid
flowchart LR
  subgraph build[publish workflow on main, daily]
    b[build app, unsigned, vulnerable] --> s[cosign sign: keyless, GitHub OIDC]
    s --> a[attest: SLSA provenance, CycloneDX SBOM, Trivy scan]
  end
  a -->|push| reg[(ghcr.io)]
  s -->|record| rekor[(Rekor)]
  pod[pod create] --> api[API server]
  api -->|in-process| vap[registry allowlist: this path, by digest]
  api -->|webhook| kyv[Kyverno: signer, provenance, SBOM, scan]
  kyv -->|reads| reg
  kyv -.->|inclusion proof checked offline, key from the Sigstore TUF root| rekor
```

- **Publish** (`.github/workflows/publish.yml`): three demo images, built for amd64 and arm64. `app` and `vulnerable` are signed with the workflow's own identity, and each gets three signed attestations: SLSA v1 provenance written in the job, a CycloneDX SBOM from Syft, and a Trivy scan. `unsigned` is pushed and never signed. The scan is re-run daily.
- **Verification** (`policies/verify-images.yaml`): one Kyverno ImageValidatingPolicy, `failurePolicy: Fail`, bound to namespaces labelled `supply-chain.heyvaldemar.com/verified`. One exact signer; the provenance must name this repository; the scan must contain an operating system's packages and no critical finding.
- **The floor** (`policies/registry-allowlist.yaml`): a ValidatingAdmissionPolicy the API server evaluates itself. Images come from this repository's registry path, by digest.
- **Kyverno** (`scripts/install-kyverno.sh`, `kyverno/`): the chart pinned by version, every image it runs pinned by digest.

## Quickstart

Needs Docker. The tools (kind, kubectl, helm, kubeconform) are installed at pinned versions and hashes into `.cache/bin`. Nothing is built or signed locally; the cluster pulls the images the publish workflow pushed last.

```bash
make up      # kind cluster, Kyverno, the namespace and both policies
make test    # the full e2e suite
make check   # the static checks and their planted violations
make down
```

## Cost

Nothing in a cloud. The cluster is kind on one machine; the images live in GitHub's registry, free for a public repository, and Sigstore's public instance is free. CI is two GitHub-hosted runs a day: the publish workflow (build, sign, attest, scan) and a fresh kind cluster with every check, two to three minutes each. On EKS the cost is Kyverno's admission controller at three replicas. And latency: each new pod waits on the registry and the transparency log.

## What it does not do

The [threat model](docs/threat-model.md) lists every threat with its control and check, five findings from the build, and what is not covered: with Kyverno down, unsigned images from the allowed registry path are admitted; a scan is only as fresh as the last publish run; the provenance is Build L2, written by the job that builds; a running pod is not re-checked when its image's scan turns critical; the registry is on the admission path.

## Repository

```text
images/               the three demo images: app, unsigned, vulnerable
.github/workflows/    publish (build, sign, attest), e2e, verify, scorecard
policies/             the Kyverno image policy and the native registry allowlist
manifests/            the verified namespace
kind/ kyverno/        the cluster and Kyverno's chart, values and image pins
tests/e2e/            the checks against a running cluster, and the planted pods
tests/static/         the planted violations for the static checks
scripts/              install the tools and Kyverno, the static checks
docs/                 the threat model and the decisions
```

## Decisions

[`docs/decisions/`](docs/decisions/): Kyverno's ImageValidatingPolicy over a second admission engine; keyless signing pinned to one workflow; provenance, an SBOM and a scan as gates; a native floor under the webhook. Each ends with how the choice would be explained to a customer.

This repository is the supply chain half of [aws-eks-reference-platform](https://github.com/heyvaldemar/aws-eks-reference-platform), whose threat model lists unsigned images as its largest open risk. The [agent sandbox](https://github.com/heyvaldemar/kubernetes-ai-agent-sandbox) is the other piece next to it.

## Questions, bugs and changes

Open an [issue](https://github.com/heyvaldemar/kubernetes-supply-chain-admission/issues) for a bug, a question or an idea. Security reports go privately, as [SECURITY.md](SECURITY.md) describes. Changes are welcome as pull requests: CI runs the same checks on them as on main, and a change ships with the check that proves it.

## How this is built

One maintainer and an AI agent. The agent writes most of the code; the decisions are mine, and so is the verification. Nothing merges on the agent's report that it works: it merges on the checks above, and each of them has been shown the failure it exists to catch. The empty scan and the `.predicate` path in the threat model came from checks that failed during the build.

## License

[MIT](LICENSE).
