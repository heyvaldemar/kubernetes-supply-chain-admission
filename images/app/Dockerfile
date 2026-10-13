# The image the cluster should run: built here, signed by this repository's
# publish workflow, with an SBOM, provenance and a clean scan attached. Alpine,
# not busybox: a scanner that cannot tell which distribution an image is
# reports nothing, and nothing is not a clean scan.
FROM docker.io/library/alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8
LABEL org.opencontainers.image.source="https://github.com/heyvaldemar/kubernetes-supply-chain-admission"
USER 65534:65534
CMD ["sleep", "3600"]
