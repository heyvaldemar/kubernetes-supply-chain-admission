# The image the cluster should run: built here, signed by this repository's
# publish workflow, with an SBOM, provenance and a clean scan attached. Alpine,
# not busybox: a scanner that cannot tell which distribution an image is
# reports nothing, and nothing is not a clean scan.
FROM docker.io/library/alpine:3.22@sha256:2e0b81d60597f449baa56dc25d355367869d2dca4cd57e866f1e2b52af3eb55f
LABEL org.opencontainers.image.source="https://github.com/heyvaldemar/kubernetes-supply-chain-admission"
USER 65534:65534
CMD ["sleep", "3600"]
