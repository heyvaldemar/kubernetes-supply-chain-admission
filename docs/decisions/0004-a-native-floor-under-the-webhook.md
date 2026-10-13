# 4. A native floor under the webhook

- Status: accepted
- Date: 2026-10-13

## Context

Signature verification runs in Kyverno's webhook. Kyverno removes its webhook configurations when its admission controller is scaled to zero, and a webhook that is gone verifies nothing.

## Decision

A ValidatingAdmissionPolicy (`policies/registry-allowlist.yaml`), evaluated by the API server itself, refuses any image outside this repository's registry path and any image by tag, in the same namespaces. It cannot check signatures; it holds while Kyverno does not.

## Consequences

- With Kyverno at zero, the e2e run shows images from anywhere else still refused, and an unsigned image from the allowed path admitted. The second half is the gap, measured on purpose so a change in either half fails the run.
- The allowlist and the signer describe the same images only when push rights to the registry path belong to the signing workflow alone; that is a registry setting outside this repository.
- On a real cluster the gap is closed operationally: three admission controller replicas, a disruption budget, and an alert on replicas or webhook configurations disappearing.

## Alternatives

- **No floor.** Simpler, and the Kyverno-down window admits anything from anywhere.
- **A mutating rule that adds a marker only Kyverno can set, and a native rule that requires it.** Fails closed when Kyverno is down, and moves the trust question to who else can set the marker.

## How to explain this to a customer

If the service that checks signatures ever stops, a second rule built into Kubernetes still refuses software from outside our registry. Software from our registry in that window is the remaining exposure, and it is closed by running the checker redundantly and paging someone the moment it stops.
