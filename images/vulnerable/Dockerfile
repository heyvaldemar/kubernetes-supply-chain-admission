# Signed, with an SBOM and provenance, and built on a base with a known
# critical vulnerability (CVE-2021-36159 in apk-tools). The signature says
# who built it; the scan says it should not run.
FROM docker.io/library/alpine:3.10@sha256:451eee8bedcb2f029756dc3e9d73bab0e7943c1ac55cff3a4861c52a0fdd3e98
LABEL org.opencontainers.image.source="https://github.com/heyvaldemar/kubernetes-supply-chain-admission"
USER 65534:65534
CMD ["sleep", "3600"]
