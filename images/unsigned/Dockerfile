# Built and pushed by the same workflow, never signed: what a compromised
# build, a manual push or a typo in a tag would put in the registry.
FROM docker.io/library/alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8
LABEL org.opencontainers.image.source="https://github.com/heyvaldemar/kubernetes-supply-chain-admission"
# A different file, so this image's digest differs from the signed one's.
COPY unsigned.txt /unsigned.txt
USER 65534:65534
CMD ["sleep", "3600"]
