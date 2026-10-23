# Kyverno attestation order (reproduction)

A reproduction for Kyverno's `ImageValidatingPolicy`, the policy type this repository runs, of [kyverno/kyverno#18000](https://github.com/kyverno/kyverno/issues/18000): when an image carries several attestations of one predicate type, `extractPayload()` returns whichever one the registry's referrers index lists last, not the newest.

It is not one of this repository's checks. It runs when started by hand, in [`.github/workflows/attestation-order-repro.yml`](../../.github/workflows/attestation-order-repro.yml):

1. Build one image and attest it twice with cosign v3.1.3, keyless, with the same predicate type: `{"which": "first"}`, then `{"which": "second"}`.
2. Start kind with the Kyverno this repository pins (`scripts/install-kyverno.sh`) and apply [`policy.yaml`](policy.yaml), which verifies the attestations and admits a pod only when `extractPayload()` returns the one that says `second`, the newer.
3. Put the two bundles in the index newest last, restart Kyverno's admission controller so nothing is cached, and ask the API server about a pod with the image (server-side dry run).
4. Put them newest first, restart, ask again.

Reproduced means the two answers differ: admitted with the newer bundle listed last, refused with it listed first. Nothing changes between the two questions except the order of the index. The image, its digest and both signed attestations stay the same.

Reproduced with Kyverno 1.19.1 ([38594942252](https://github.com/heyvaldemar/kubernetes-supply-chain-admission/actions/runs/38594942252), 2026-10-14) and again with 1.19.2 ([39898566528](https://github.com/heyvaldemar/kubernetes-supply-chain-admission/actions/runs/39898566528), 2026-10-23): admitted with the newer bundle listed last, refused with it listed first, `extractPayload()` returning the older one.

Where it comes from in Kyverno 1.19.1: `VerifyAttestationSignature` in `pkg/image/verifiers/ivpol/cosign/verifier.go` calls `image.AddVerifiedIntotoPayloads(gotType, payload)` for every verified attestation of the requested type, and in kyverno/sdk (`extensions/imagedataloader/loader.go`) that is a map keyed by predicate type, so each one overwrites the one before. cosign v3.1.2 returns the bundles in index order.

To run it in a fork: Actions, "Kyverno attestation order (reproduction)", Run workflow on `main`. The policy names the fork's own workflow as the signer. The image's package has to be public, because Kyverno reads the registry anonymously; `order.py` stops with that message when it is not.
