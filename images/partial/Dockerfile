# Three images the publish workflow signs with its own identity and then
# leaves one attestation off: no-provenance, no-sbom and no-scan. Each must be
# refused for the one it lacks, so the policy's requirement for each
# attestation is seen to fail on its own and not only behind the signature.
# The same base as app; the label makes three digests, so no image shares
# another's attestations.
FROM docker.io/library/alpine:3.22@sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f
ARG LACKS
LABEL org.opencontainers.image.source="https://github.com/heyvaldemar/kubernetes-supply-chain-admission"
LABEL io.github.heyvaldemar.lacks="${LACKS}"
USER 65534:65534
CMD ["sleep", "3600"]
