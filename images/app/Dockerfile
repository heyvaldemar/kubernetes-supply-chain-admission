# The image the cluster should run: built here, signed by this repository's
# publish workflow, with an SBOM, provenance and a clean scan attached.
FROM docker.io/library/busybox:1.37@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e
LABEL org.opencontainers.image.source="https://github.com/heyvaldemar/kubernetes-supply-chain-admission"
USER 65534:65534
CMD ["sleep", "3600"]
