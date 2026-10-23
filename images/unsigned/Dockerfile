# Built and pushed by the same workflow, never signed: what a compromised
# build, a manual push or a typo in a tag would put in the registry.
FROM docker.io/library/alpine:3.22@sha256:d406446bc05b82480756ce8f1287964d28768c23955fa9480d2a74a2eae7a654
LABEL org.opencontainers.image.source="https://github.com/heyvaldemar/kubernetes-supply-chain-admission"
# A different file, so this image's digest differs from the signed one's.
COPY unsigned.txt /unsigned.txt
USER 65534:65534
CMD ["sleep", "3600"]
