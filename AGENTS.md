# Working on this repository as an agent

Most of the code here is written by an AI agent, and the decisions and the verification are the maintainer's. This file is what the agent is held to. A reviewer can hold it to the same rules.

## What this repository claims

Every line of the README's "What is proven, and how" is a check that runs in CI: `tests/e2e/run.sh` on a fresh kind cluster, `scripts/verify-published.sh` against the registry, or, in Verify, `scripts/validate.sh` with its planted violations and `scripts/referrers.py selftest`. A claim with no check is not written. A control with no check goes under the threat model's residual risks, not its controls. It is a reference architecture that runs on kind, and nothing says otherwise: no wording about production use or a certification in the README, the threat model or the decision records.

## Before changing anything

- Read the decision record that covers it, under `docs/decisions/`, and `docs/threat-model.md`. A change that alters a decision amends that record or adds one, in the same format, ending with how the choice is explained to a customer, and lists it in `docs/decisions/README.md`.
- A change to what is admitted or refused updates the threat model's table in the same commit: the threat, the control, and the check that is its evidence.
- The signer identity, the registry path and the namespace label are written in more than one file (the policies, `manifests/namespace.yaml`, `scripts/verify-published.sh`, `tests/e2e/run.sh`, the plants, the README). Find every copy before changing one. A different signer is a policy change (ADR 2).
- `make check` runs the static checks and shows each one its planted violation (`tests/static/plants.tsv`). It must stay all caught, none missed, none stale. `python3 scripts/referrers.py selftest` runs the bundle selection rule on planted data.

## A check is trusted only after it has failed

A new or changed check ships with the violation it exists for: a planted pod under `tests/e2e/plants/` whose `# expect:` line is the refusal it must produce, a row in `tests/static/plants.tsv`, a case in `scripts/referrers.py selftest`, or a deliberate sabotage run whose failing output is recorded in the commit message. A refusal counts only next to the control, `tests/e2e/plants/signed.yaml`, which must be admitted and run, so no check passes because the cluster refuses everything. A check that has never been seen to fail proves nothing.

## Proving a risky change

Run the e2e and the static checks on a branch before it reaches main:

```bash
gh workflow run e2e.yml --ref <branch>
gh workflow run verify.yml --ref <branch>
```

A pull request to main runs both. `scripts/status.py` reads e2e runs on main only, so a branch run never moves the badges.

The e2e reads the images that main's publish run pushed last, so a change under `images/` or to `.github/workflows/publish.yml` cannot be proved on a branch. After it merges, wait for the publish run to finish, then run `gh workflow run e2e.yml --ref main`.

A Kyverno upgrade is a risky change. The threat model's findings that name Kyverno 1.19.1, and `repro/attestation-order`, describe that version's behaviour: check each against the new one.

## Pins

Each pin has a home, and `scripts/check-freshness.py` compares them all with upstream on Verify's weekly schedule. It reports and changes nothing.

- Base images by digest in `images/*/Dockerfile`.
- Kyverno's chart by version in `scripts/install-kyverno.sh` (`CHART_VERSION`), every image it runs by digest in `kyverno/images.yaml`.
- The kind node by digest in `kind/cluster.yaml`.
- Tools by version and sha256 per platform in `tools.lock`, each hash checked against the publisher's own checksum file.
- CI images in `ci-images.pins`; Syft and Trivy in `.github/workflows/publish.yml`; cosign through `cosign-release` in the e2e, publish and repro workflows.
- The Kubernetes schemas at one commit in `scripts/validate.sh`.
- Actions by commit SHA, moved by Dependabot (`.github/dependabot.yml`) and merged only after e2e and Verify pass.

Some pins have copies: the Alpine 3.22 digest is in both Dockerfiles, `tests/static/plants.tsv` and the repro workflow, and the other signer's image is in `tests/e2e/run.sh` and `tests/e2e/plants/other-signer.yaml`. Move every copy; a plant whose text is gone is reported stale. `images/vulnerable` stays on Alpine 3.10: its critical CVE is the point.

## Numbers

A number is read from a run, never typed from memory. The README's second row of badges is written by `.github/workflows/status.yml` (`scripts/status.py`) into the `status` branch from the e2e runs on main, and nothing edits that branch by hand. The block under "What the run reports" is copied from a run's output, and `docs/demo/` is a recorded `make test` with only the waits cut. A measured number in prose, such as admission time in the threat model, names the runs it came from in the commit.

When runs differ, find what changed (the registry, the runner, Kyverno, the bundles on an image) before calling it noise: chasing e2e failures on the webhook's timeout is how the attestation pile-up was found. A gate or a timeout is set from measurement and the record says why, as the policy's comment does for the webhook's 30 seconds. It is never loosened to get a green run without that.

## Releases

- Fill `CHANGELOG.md` `[Unreleased]` in the same commit as the change.
- Tag only a commit whose e2e and Verify are green, or a docs-only commit right after one, and say which in the release notes: what is new, what was found while building it, how it was checked.
- Publishing a release runs `.github/workflows/release-assets.yml`: an archive of the tag, its keyless signature (`.tar.gz.sigstore.json`) and SLSA provenance (`.intoto.jsonl`). Verify them the way a stranger would, with `cosign verify-blob` and `slsa-verifier verify-artifact --source-tag <tag>`, as the workflow's header shows.

## Writing

Plain and specific. No em dashes, no marketing words, no claim the evidence does not carry. Name runs, commits and files. A finding from the build goes in the threat model with the check that caught it; one that belongs upstream is reported there and linked by number, as kyverno/kyverno#18023 is. Commits are authored `Vladimir Mikhalev <10498744+heyvaldemar@users.noreply.github.com>` and carry no AI attribution lines.

## Never

- Print a secret or a credential, or pass one as a command-line argument. Scripts read them from the environment (`REGISTRY_USER` and `REGISTRY_TOKEN` in `scripts/referrers.py`), and an auth error prints its HTTP status, never its body: a registry may echo the credential. Signing is keyless; there is no key to keep.
- Weaken a check, a policy, a test or a gate to get a run green: no `failurePolicy: Ignore`, no signer pattern, no image match narrower than `*`, no attestation or validation dropped, no plant edited until it stops failing, no `# expect:` line rewritten to match what the cluster now says.
- Retry a refusal. The e2e run applies once more only when the webhook timed out without a decision, and records that as a NOTE.
- Change the Kyverno-down check to pass. The unsigned image admitted with Kyverno at zero is the measured gap (ADR 4); if it changes, the threat model and ADR 4 change with it.
- Sign, attest or push an image by hand, or run the publish workflow from a branch. The publish workflow on main is the one signer the policy accepts, and its run pushes the `latest` tags every e2e run reads.
- Attach a second attestation of one type to a published image, or remove `scripts/referrers.py prune` from the publish run. With two of a kind, which one Kyverno reads depends on the order of GHCR's referrers index (kyverno/kyverno#18023).
- Change `repro/attestation-order` to agree with the policy. It reproduces Kyverno's behaviour for the upstream report and is not one of this repository's checks.
- Touch anything outside this repository's own CI to test a change: no cloud resources, and no outside services beyond those CI already uses (GitHub's registry, Sigstore's public instance, the pinned downloads).
