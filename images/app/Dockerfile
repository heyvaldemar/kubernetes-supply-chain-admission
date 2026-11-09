# The image the cluster should run: built here, signed by this repository's
# publish workflow, with an SBOM, provenance and a clean scan attached. Alpine,
# not busybox: a scanner that cannot tell which distribution an image is
# reports nothing, and nothing is not a clean scan.
FROM docker.io/library/alpine:3.22@sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f
LABEL org.opencontainers.image.source="https://github.com/heyvaldemar/kubernetes-supply-chain-admission"
USER 65534:65534
CMD ["sleep", "3600"]
