# Built and pushed by the same workflow, never signed: what a compromised
# build, a manual push or a typo in a tag would put in the registry.
FROM docker.io/library/alpine:3.22@sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f
LABEL org.opencontainers.image.source="https://github.com/heyvaldemar/kubernetes-supply-chain-admission"
# A different file, so this image's digest differs from the signed one's.
COPY unsigned.txt /unsigned.txt
USER 65534:65534
CMD ["sleep", "3600"]
