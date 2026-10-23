# 5. No image runs while Kyverno is away

- Status: accepted
- Date: 2026-10-21

## Context

ADR 4 put a native floor under the webhook and measured what it left: with Kyverno's admission controller at zero, an unsigned image from this repository's own registry path was admitted, because the registry allowlist cannot check a signature. The e2e run asserted that gap on purpose, and the threat model listed it as residual, to be closed by running Kyverno redundantly and paging on its absence.

The gap has a mechanism. Kyverno removes its own webhook configurations when its Deployment is at zero replicas or being deleted (`pkg/webhooks/server.go`, `cleanup`, when `runtime.IsGoingDown()`, Kyverno 1.19.1, unchanged in 1.19.2), so `failurePolicy: Fail` has nothing left to fail with. Replicas and a disruption budget keep Kyverno up through a node loss; they do nothing against someone scaling it to zero or uninstalling it, which is exactly when the configurations go. The air-gapped agent hit the same hole on a model in its daily game day and closed it natively (its ADR 17).

## Decision

- **The API server refuses every pod in a verified namespace while Kyverno's webhook for the image policy is missing.** `policies/kyverno-guard.yaml` is a ValidatingAdmissionPolicy whose parameter is Kyverno's resource webhook configuration, `kyverno-resource-validating-webhook-cfg`, with `parameterNotFoundAction: Deny`, and which requires that configuration to hold the webhook for `verify-images` with `failurePolicy: Fail`. Kyverno scaled down, uninstalled, its configuration deleted by anyone, or the webhook turned to Ignore: refused, by the API server itself. Kyverno back, it writes the configuration again, and verified images are admitted again.
- **The e2e run's step 6 now requires the opposite of what it measured.** With Kyverno at zero, it waits up to half a minute for the configurations to go, records which way it went, and requires the unsigned image, the signed image and an image from another registry each refused. Then Kyverno back, and the unsigned image refused for its signature again.
- **The CI waits for the webhook before any pod.** The guard goes on with the other policies; the e2e workflow waits for Kyverno to register the webhook under its name and stops if it never does, rather than run with a guard that would refuse everything for good.
- **Static check `policy`** holds the guard to the webhook the image policy actually has and to `Deny` when it is missing, with a plant for each.

## Consequences

- With Kyverno away, no new pod starts in a verified namespace, a verified image included: an outage of deployments there, not of running pods. Running Kyverno three times over and paging on its absence still matter; they now shorten an outage instead of closing a hole.
- The guard names Kyverno's configuration and its webhook by the names Kyverno 1.19.1 gives them, and 1.19.2 gives them still: its renaming (kyverno/kyverno#17617) is for namespaced image policies. An upgrade that renames either makes the guard refuse everything in the verified namespace, which the e2e catches before anything ships.
- Uninstalling Kyverno now stops pods from starting in the verified namespace until the guard is removed too. That is the point.

## Alternatives

- **Keep the gap, measured.** ADR 4's choice. It made the exposure honest; this makes it go away.
- **A mutating rule that adds a marker only Kyverno can set, and a native rule that requires it** (ADR 4's alternative). Also fails closed, and moves the trust question to whoever else can set the marker; the guard asks the API server about Kyverno's own configuration instead, which only someone who can change admission configuration can fake.

## How to explain this to a customer

The service that checks every image's signature can be stopped, and when it is, by design it steps out of the way. Until now a small window remained in which an unsigned image from our own registry would have started. Kubernetes now enforces a rule of its own: while that checker is not in place, nothing new starts where checked images are required. Running workloads keep running, and a daily test stops the checker and shows it.
