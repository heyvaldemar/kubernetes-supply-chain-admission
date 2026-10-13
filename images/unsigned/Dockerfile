# Built and pushed by the same workflow, never signed: what a compromised
# build, a manual push or a typo in a tag would put in the registry.
FROM docker.io/library/busybox:1.37@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e
LABEL org.opencontainers.image.source="https://github.com/heyvaldemar/kubernetes-supply-chain-admission"
# A different file, so this image's digest differs from the signed one's.
COPY unsigned.txt /unsigned.txt
USER 65534:65534
CMD ["sleep", "3600"]
