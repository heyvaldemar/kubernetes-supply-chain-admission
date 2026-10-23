# The image the cluster should run: built here, signed by this repository's
# publish workflow, with an SBOM, provenance and a clean scan attached. Alpine,
# not busybox: a scanner that cannot tell which distribution an image is
# reports nothing, and nothing is not a clean scan.
FROM docker.io/library/alpine:3.22@sha256:d406446bc05b82480756ce8f1287964d28768c23955fa9480d2a74a2eae7a654
LABEL org.opencontainers.image.source="https://github.com/heyvaldemar/kubernetes-supply-chain-admission"
USER 65534:65534
CMD ["sleep", "3600"]
