#!/usr/bin/env python3
"""referrers.py - one Sigstore bundle of each kind per image.

    referrers.py prune IMAGE@DIGEST ...   rewrite each image's referrers index
    referrers.py check IMAGE[:TAG|@DIGEST] ...  exit 1 if any kind is there twice
    referrers.py selftest                 the selection rule, on planted data

cosign attaches every signature and attestation to the image as an OCI
referrer. GHCR has no referrers API, so cosign keeps them in an index under
the fallback tag sha256-<digest> and appends to it on every run. The images
here build reproducibly, so the daily publish run attaches four more bundles
to the same digest, and Kyverno 1.19 verifies every bundle on the image, once
for each attestation the policy declares, on every admission. The work
grows by four bundles a day, with no limit.

It also decides which scan the policy reads. With several attestations of
one type, Kyverno keeps the last it verified (AddVerifiedIntotoPayloads
writes a map keyed by predicate type), and GHCR's index is not in the order
the bundles were made.

prune keeps the newest bundle of each kind by its
org.opencontainers.image.created annotation, later in the index on a tie,
and writes the index back. Referrers that are not Sigstore bundles are kept
as they are. The bundles left out stay in the registry, untagged and
unreferenced. prune reads REGISTRY_USER and REGISTRY_TOKEN from the
environment; check reads anonymously.
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

BUNDLE = "application/vnd.dev.sigstore.bundle.v0.3+json"
INDEX = "application/vnd.oci.image.index.v1+json"
MANIFEST = "application/vnd.oci.image.manifest.v1+json"


def kind_of(annotations):
    """What a bundle vouches for: its predicate type, or its content kind."""
    return annotations.get("dev.sigstore.bundle.predicateType") or annotations.get("dev.sigstore.bundle.content", "")


def select(entries):
    """entries: (descriptor, annotations) in index order. Returns (keep, drop),
    keep in index order. One Sigstore bundle per kind, the newest."""
    newest = {}
    for pos, (desc, ann) in enumerate(entries):
        if desc.get("artifactType") != BUNDLE:
            continue
        k = kind_of(ann)
        key = (ann.get("org.opencontainers.image.created", ""), pos)
        if k not in newest or key >= newest[k][0]:
            newest[k] = (key, pos)
    kept = {pos for _, pos in newest.values()}
    keep, drop = [], []
    for pos, (desc, ann) in enumerate(entries):
        (keep if desc.get("artifactType") != BUNDLE or pos in kept else drop).append((desc, ann))
    return keep, drop


class Registry:
    def __init__(self, repo, push):
        self.repo = repo
        scope = "repository:%s:%s" % (repo, "pull,push" if push else "pull")
        req = urllib.request.Request("https://ghcr.io/token?" + urllib.parse.urlencode({"scope": scope, "service": "ghcr.io"}))
        if push:
            user, token = os.environ["REGISTRY_USER"], os.environ["REGISTRY_TOKEN"]
            req.add_header("Authorization", "Basic " + base64.b64encode(("%s:%s" % (user, token)).encode()).decode())
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                self.token = json.load(r)["token"]
        except urllib.error.HTTPError as e:
            # The body is not printed: a registry may echo the credential.
            sys.exit("registry refused a token for %s: HTTP %d" % (repo, e.code))

    def _call(self, method, path, accept=None, body=None, content_type=None):
        req = urllib.request.Request("https://ghcr.io/v2/%s/%s" % (self.repo, path), data=body, method=method)
        req.add_header("Authorization", "Bearer " + self.token)
        if accept:
            req.add_header("Accept", accept)
        if content_type:
            req.add_header("Content-Type", content_type)
        return urllib.request.urlopen(req, timeout=30)

    def digest(self, tag):
        accept = ", ".join([INDEX, MANIFEST, "application/vnd.docker.distribution.manifest.list.v2+json"])
        with self._call("HEAD", "manifests/" + tag, accept=accept) as r:
            return r.headers["Docker-Content-Digest"]

    def get(self, ref, accept):
        try:
            with self._call("GET", "manifests/" + ref, accept=accept) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            raise

    def put(self, ref, doc, media_type):
        with self._call("PUT", "manifests/" + ref, body=json.dumps(doc).encode(), content_type=media_type):
            pass


def read(image, push):
    name, _, digest = image.partition("@")
    tag = None
    if not digest and ":" in name.rsplit("/", 1)[-1]:
        name, tag = name.rsplit(":", 1)
    if not name.startswith("ghcr.io/") or not (digest.startswith("sha256:") or tag):
        sys.exit("expected ghcr.io/<repository>@sha256:<digest> or :<tag>, got %s" % image)
    reg = Registry(name[len("ghcr.io/"):], push)
    if tag:
        digest = reg.digest(tag)
    tag = "sha256-" + digest[len("sha256:"):]
    index = reg.get(tag, INDEX)
    entries = []
    for desc in (index or {}).get("manifests", []):
        ann = {}
        if desc.get("artifactType") == BUNDLE:
            ann = (reg.get(desc["digest"], MANIFEST) or {}).get("annotations", {})
        entries.append((desc, ann))
    return reg, tag, index, entries


NAMES = {
    "https://sigstore.dev/cosign/sign/v1": "signature",
    "https://slsa.dev/provenance/v1": "provenance",
    "https://cyclonedx.org/bom": "sbom",
    "https://cosign.sigstore.dev/attestation/vuln/v1": "scan",
}


def summary(entries):
    counts = {}
    for desc, ann in entries:
        if desc.get("artifactType") == BUNDLE:
            k = NAMES.get(kind_of(ann), kind_of(ann))
            counts[k] = counts.get(k, 0) + 1
    return ", ".join("%s %d" % kv for kv in sorted(counts.items())) or "none"


def prune(images):
    for image in images:
        reg, tag, index, entries = read(image, push=True)
        keep, drop = select(entries)
        if not drop:
            print("%s: one of each already (%s)" % (image, summary(entries)))
            continue
        index["manifests"] = [desc for desc, _ in keep]
        reg.put(tag, index, index.get("mediaType", INDEX))
        print("%s: kept %s; dropped %d older" % (image, summary(keep), len(drop)))
    return 0


def check(images):
    failed = 0
    for image in images:
        _, _, _, entries = read(image, push=False)
        _, drop = select(entries)
        if drop:
            print("  FAIL  %s: more than one bundle of a kind (%s)" % (image, summary(entries)))
            failed = 1
        else:
            print("  ok    %s: one bundle of each kind (%s)" % (image, summary(entries)))
    return failed


def selftest():
    def b(kind, created, content="dsse-envelope"):
        ann = {"dev.sigstore.bundle.content": content, "org.opencontainers.image.created": created}
        if kind:
            ann["dev.sigstore.bundle.predicateType"] = kind
        b.n += 1
        return ({"artifactType": BUNDLE, "digest": "sha256:%064d" % b.n}, ann)
    b.n = 0
    vuln, sbom, sig = "https://cosign.sigstore.dev/attestation/vuln/v1", "https://cyclonedx.org/bom", "https://sigstore.dev/cosign/sign/v1"
    other = ({"artifactType": "application/vnd.example.notary+json", "digest": "sha256:other"}, {})
    # Out of creation order. On GHCR on 2026-10-13 it was the SBOMs and the
    # signatures that were reversed; the scans here are reversed the same way.
    entries = [b(sbom, "2026-10-13T04:35:18Z"), b(vuln, "2026-10-13T04:35:44Z"), other,
               b(vuln, "2026-10-13T04:31:30Z"), b(sig, "2026-10-13T04:30:26Z"), b(sbom, "2026-10-13T04:31:08Z"),
               b("", "2026-10-13T04:30:00Z", content="message-signature"), b("", "2026-10-13T04:40:00Z", content="message-signature"),
               b(sig, "2026-10-13T04:30:26Z")]
    keep, drop = select(entries)
    got = [(kind_of(a), a.get("org.opencontainers.image.created")) for d, a in keep if d["artifactType"] == BUNDLE]
    want = [(sbom, "2026-10-13T04:35:18Z"), (vuln, "2026-10-13T04:35:44Z"), ("message-signature", "2026-10-13T04:40:00Z"), (sig, "2026-10-13T04:30:26Z")]
    cases = [
        ("the newest of each kind is kept, in index order", got == want),
        ("a referrer that is not a Sigstore bundle is kept", other in keep),
        ("on equal timestamps the later entry is kept", keep[-1] == entries[-1] and entries[4] in drop),
        ("everything else is dropped", len(drop) == len(entries) - len(keep) == 4),
        ("one of each drops nothing", select(keep) == (keep, [])),
    ]
    for name, passed in cases:
        print("  %s  %s" % ("ok  " if passed else "FAIL", name))
    return 0 if all(p for _, p in cases) else 1


if __name__ == "__main__":
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    if cmd == "selftest":
        sys.exit(selftest())
    if cmd in ("prune", "check") and args:
        sys.exit(prune(args) if cmd == "prune" else check(args))
    sys.exit(__doc__)
