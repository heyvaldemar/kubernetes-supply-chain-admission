# 6. Every image a pod uses, not only its containers

- Status: accepted
- Date: 2026-10-22

## Context

The image policy and the registry allowlist held a pod's containers to the bar, and that was the gap. A pod uses images in four places: its containers, its init containers, the ephemeral containers `kubectl debug` adds to it while it runs, and its image volumes, whose files the signed process reads.

Kyverno 1.19.1's ImageValidatingPolicy extracts the images of the first three, each under its own key (`images.containers`, `images.initContainers`, `images.ephemeralContainers`), and no image volume (`pkg/cel/compiler/images.go`); 1.19.2 is the same. [kyverno/kyverno#17555](https://github.com/kyverno/kyverno/pull/17555) would have added volumes by default; it was closed unmerged by the stale bot on 2026-10-22. The policy's validations read `images.containers` alone. The registry allowlist read containers and init containers. Both matched `pods`, and `kubectl debug` writes to the pod's `ephemeralcontainers` subresource, which a rule for `pods` does not match. So did the guard of ADR 5.

The e2e run on the branch before the fix, [39888131990](https://github.com/heyvaldemar/kubernetes-supply-chain-admission/actions/runs/39888131990), beside the signed image in a verified namespace, with the signed image admitted as an ephemeral container (the control):

- an image nobody signed, mounted as a volume: admitted;
- an image from another registry, mounted as a volume: admitted;
- an ephemeral container with an image nobody signed: admitted;
- an ephemeral container with an image from another registry: admitted;
- with Kyverno at zero, an ephemeral container: admitted, past the guard;
- an init container nobody signed: refused, but by Kyverno's `required` check ("is not verified: no policy performed a signature or attestation check on it"), not by the signature rule. No init container's provenance, SBOM or scan was ever read.

## Decision

- **The image policy reads every image the pod uses.** `images` adds an extractor for image volumes, `spec.volumes[].image.reference`; every validation reads `images.containers + images.initContainers + images.ephemeralContainers + images.volumes`, so the signature, the provenance, the SBOM and the scan apply to each.
- **The registry allowlist reads the same four**, by digest and from this repository's registry path.
- **The image policy, the allowlist and the guard match `pods/ephemeralcontainers` beside `pods`**, so `kubectl debug` meets the same three rules as creating the pod, Kyverno away included.
- **Static check `policy`** holds each of these, with six plants: a validation without volumes, no volume extractor, the subresource left out of each of the three policies, the allowlist without volumes.
- **The e2e run** keeps the four plants and the ephemeral steps beside their controls.

## Consequences

- An image volume in a verified namespace is held to everything a container image is: signed by the publish workflow, with provenance, an SBOM and a scan that read an operating system's packages. A volume that carries only data has no packages to scan, and is refused. Data that a workload needs belongs in a signed image that passes, or outside the verified namespace.
- `kubectl debug` in a verified namespace works with the signed images and nothing else. A debugging session with a toolbox image is refused there: that is the point, and the same toolbox is welcome in a namespace that is not verified.
- Kyverno's own extraction may cover volumes one day. The extractor here then reads them twice, which changes nothing; the static check keeps it until the upstream default is in the version this repository pins.

## Alternatives

- **Refuse image volumes and ephemeral containers outright in verified namespaces.** Simpler, and it takes away two things a site uses, model weights shipped as images and debugging. Verifying them keeps both.
- **Wait for #17555 or a successor.** The gap was open in this repository whatever upstream decides.

## How to explain this to a customer

A pod can pull images in four ways, and until now we checked the main one. A container that runs first, a debugging container added to a running pod, and an image mounted as a disk of files all came in without the signature check, and our daily test showed each of them getting through before we closed it. Now every image a pod uses, in any of the four ways, needs the same signature and records, and the same daily test shows each refused.
