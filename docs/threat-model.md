# Threat model

What this repository's admission policies stop, the check that proves each, and what they do not stop. A control without a check is listed as a residual risk, not as a control.

The checks are `tests/e2e/run.sh` on a fresh kind cluster with Kyverno, against the images the publish workflow pushed last (every change, and daily), and `scripts/validate.sh` with its planted violations.

## What is protected

The cluster's workloads, from code nobody meant to run there. A digest pins bytes; it says nothing about who built them, from what, or what is in them. This repository asks each image for four things before it runs: a signature by one known build, provenance that names the source, an SBOM, and a scan that read the image and found nothing critical.

## Threats, controls and evidence

| Threat | Control | Evidence |
|---|---|---|
| An image pushed by hand, or by a compromised step that does not hold the build's identity | a cosign keyless signature by exactly one workflow on `main` of this repository, checked against Sigstore's transparency log | the unsigned image, pushed by the same workflow, refused |
| An image signed, by someone else | the signer is pinned to one workflow identity, not to an account or a pattern; every image in the pod is matched, from any registry | an image signed by Sigstore's own release workflow refused by Kyverno alone; the static check fails on a signer pattern (plant) |
| An image built from somewhere else | signed SLSA provenance whose source must be this repository | provenance is required by the policy for every image; the signed image carries it |
| An image nobody can account for | a signed CycloneDX SBOM | required by the policy |
| An image with a known critical vulnerability | a signed scan, re-run daily, that must have read an operating system's packages and found nothing critical | the signed and attested image whose scan found CVE-2021-36159 refused |
| A verified image swapped for another under the same tag | references by digest only, enforced twice: by the image policy and by a native ValidatingAdmissionPolicy | the signed image referenced by tag refused |
| A verification that cannot run is read as a pass | `failurePolicy: Fail` | the static check fails on `Ignore` (plant) |

## Five findings from the build

**A scan that sees nothing is not a clean scan.** The first demo image was built on busybox. Trivy does not recognise busybox as a distribution and reported no results at all, which a policy that only counted critical findings would have read as zero. The image is now built on Alpine, and the policy requires a scan result that contains an operating system's packages before it looks at severities. Trivy exits 0 without a warning in that case, so a `--exit-code` gate passes an image it could not read; that is raised upstream in [aquasecurity/trivy discussion 11403](https://github.com/aquasecurity/trivy/discussions/11403).

**The attestation's content is one level down.** In Kyverno 1.19.1, `extractPayload()` returns the whole in-toto statement, so the provenance, the SBOM and the scan are under `.predicate`. The documentation's example reads `.bomFormat` at the top level, and it is right for what it declares: a Notary referrer, whose payload is the SBOM itself. Carried over to cosign attestations, that shape failed the provenance rule with `no such key` for every signed image, and the policy refused the one image it should run. Which payload comes back depends on how the attestation was attached, and the documentation shows one of the two. A note on the in-toto shape is proposed to the documentation in [kyverno/website pull request 2201](https://github.com/kyverno/website/pull/2201).

**Signature checks need a running webhook.** Kyverno deletes its webhook configurations when its admission controller is scaled to zero (the companion platform found this; the e2e run here repeats it). With Kyverno at zero, the unsigned image from this repository's registry path is admitted. What still holds is the native registry allowlist: images from anywhere else, or by tag, are refused by the API server itself. The e2e run measures both, and fails if either changes.

**Attestations pile up on a reproducible build.** The images build to the same digest every day, and every daily publish run signed and attested that digest again, so each run added four Sigstore bundles to it. Kyverno 1.19.1 verifies every bundle on the image, once for each attestation the policy declares, on every admission: with eight bundles on the vulnerable image the refusal took between 7 and 26 seconds against a 25-second webhook timeout, and two of ten e2e runs failed on the timeout instead of the policy. The count was growing by four a day. It also decided which scan the policy read: with two attestations of one type Kyverno keeps the one it verified last, and GHCR's referrers index is not in the order the bundles were made; [Kyverno issue 18000](https://github.com/kyverno/kyverno/issues/18000) reports the same ordering for `verifyImages` rules. The publish run now keeps the newest bundle of each kind and rewrites the index (`scripts/referrers.py`), and the e2e run fails if an image carries two of a kind.

**Rekor does not have to be called at admission.** The attestor first named Rekor's URL in a `ctlog` block, as the documentation's keyless examples do. Kyverno 1.19.1 then builds an online Rekor client for every verification. Without the block the transparency log is still required: Kyverno takes Rekor's public key from Sigstore's TUF root and checks the inclusion proof each bundle carries, offline (`checkOptions` and `getRekor` in `pkg/image/verifiers/ivpol/cosign/opts.go`). That takes Rekor off the admission path. It did not measurably shorten admission: one verified admission took 4 to 17 seconds across eight e2e runs without the online client, inside the 7 to 26 seconds seen with it. Every verification call reads the image's bundles from the registry again, once to detect the bundle format and once to verify, for the signature and for each declared attestation; that is the likelier cost, read from the code and not measured here.

## Residual risks

- **Kyverno down admits unsigned images from the allowed registry path.** Signature verification cannot be expressed in a ValidatingAdmissionPolicy; it needs the webhook. On a real cluster: Kyverno's admission controller at three replicas with a PodDisruptionBudget, an alert on its replicas and on the deletion of its webhook configurations, and push rights to the registry path held by the signing workflow alone, so the allowlist and the signature describe the same set of images. In this demo the same workflow also pushes the unsigned image, on purpose.
- **A scan is as fresh as the last publish run.** The publish run keeps the newest scan on each image and drops the older ones from the referrers index; they stay in the registry, unreferenced. If the daily run stops, the one scan left grows older and the policy still accepts it, because it does not read the scan's `metadata.scanFinishedOn`. A rule on that field, or an alert on the publish workflow, would close it.
- **Provenance is generated in the build job.** The SLSA v1 provenance is written and signed by the same job that builds the image (Build L2). A compromised build step could write false provenance; an isolated generator (L3) would not let it.
- **The policy trusts the scanner's database on the day of the scan.** A critical vulnerability published after the last scan is invisible until the next one; the daily re-scan bounds that to a day.
- **Admission time only.** A pod already running is not re-checked when its image's scan turns critical. Kyverno's background scanning or a report on running images would be the next step.
- **The registry is on the path.** Verification needs GitHub's registry reachable at admission, and Sigstore's TUF repository when Kyverno first loads its trust root; Rekor is not called. When the registry is not reachable, `failurePolicy: Fail` refuses new pods.

## How to explain this to a customer

Before any software runs on the cluster, the cluster checks four things about it: that our own build pipeline signed it, that it records where it was built from, that it comes with a list of what is inside, and that a scan done in the last day found nothing critical. Software that fails any check is refused, with the reason. If the checking service itself goes down, a second rule built into Kubernetes still refuses anything from outside our registry; closing the remaining gap is a matter of running the checker redundantly and alerting the moment it stops.
