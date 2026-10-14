#!/usr/bin/env python3
"""order.py newest-last|newest-first IMAGE@DIGEST - put the image's Sigstore
bundles in that order in its referrers index, by their created annotation, and
print the order that results. Uses scripts/referrers.py for the registry calls;
REGISTRY_USER and REGISTRY_TOKEN must be able to push."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "scripts"))
from referrers import BUNDLE, INDEX, read  # noqa: E402

CREATED = "org.opencontainers.image.created"


def main(order, image):
    reg, tag, index, entries = read(image, push=True)
    bundles = sorted((e for e in entries if e[0].get("artifactType") == BUNDLE), key=lambda e: e[1].get(CREATED, ""))
    if order == "newest-first":
        bundles.reverse()
    others = [e for e in entries if e[0].get("artifactType") != BUNDLE]
    index["manifests"] = [d for d, _ in bundles + others]
    reg.put(tag, index, index.get("mediaType", INDEX))
    # Read back anonymously, the way Kyverno reads it: a private package fails here.
    try:
        _, _, _, now = read(image, push=False)
    except Exception as e:  # urllib's HTTPError, or a refused token
        sys.exit("the referrers index cannot be read anonymously (%s); make the package public" % type(e).__name__)
    print("%s: %s" % (order, ", ".join(a.get(CREATED, "?") for d, a in now if d.get("artifactType") == BUNDLE)))


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("newest-last", "newest-first"):
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
