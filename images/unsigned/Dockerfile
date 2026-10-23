# Built and pushed by the same workflow, never signed: what a compromised
# build, a manual push or a typo in a tag would put in the registry.
FROM docker.io/library/alpine:3.22@sha256:2e0b81d60597f449baa56dc25d355367869d2dca4cd57e866f1e2b52af3eb55f
LABEL org.opencontainers.image.source="https://github.com/heyvaldemar/kubernetes-supply-chain-admission"
# A different file, so this image's digest differs from the signed one's.
COPY unsigned.txt /unsigned.txt
USER 65534:65534
CMD ["sleep", "3600"]
