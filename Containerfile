# Mandara OS: a bootable container image (bootc) built around Mandara Shell
# and MangoWM, for x86_64 and aarch64.
#
#   podman build --platform linux/amd64 --build-arg BASE_IMAGE=ghcr.io/ublue-os/base-main:45 -t mandara-os .
#   podman build --platform linux/arm64 --build-arg BASE_IMAGE=quay.io/fedora/fedora-bootc:45 -t mandara-os .
#
# Universal Blue's base-main is published for x86_64 only, so aarch64 builds
# on Fedora's own bootc image (same Fedora release, no RPM Fusion codecs).

ARG FEDORA_VERSION=45
ARG BASE_IMAGE=ghcr.io/ublue-os/base-main:${FEDORA_VERSION}

# ---------------------------------------------------------------------------
# Stage 1: compile scenefx + MangoWM with clang/ThinLTO and fetch the prebuilt
# binaries the image ships (Mandara, the Rust CLI tools, fonts, cursors).
# ---------------------------------------------------------------------------
FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION} AS builder

ARG TARGETARCH
# "latest" follows each project's newest GitHub release.
ARG MANDARA_VERSION=latest
ARG MANGO_VERSION=latest
# scenefx is pinned to the series MangoWM's meson.build asks for.
ARG SCENEFX_VERSION=0.5

COPY build_files/builder.sh /tmp/builder.sh
RUN --mount=type=cache,dst=/var/cache/libdnf5,sharing=locked \
    TARGETARCH="${TARGETARCH}" MANDARA_VERSION="${MANDARA_VERSION}" \
    MANGO_VERSION="${MANGO_VERSION}" SCENEFX_VERSION="${SCENEFX_VERSION}" \
    bash /tmp/builder.sh

# ---------------------------------------------------------------------------
# Stage 2: the operating system image.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE}

ARG TARGETARCH
ARG FEDORA_VERSION

COPY --from=builder /out/ /
COPY system_files/ /
COPY build_files/build.sh /tmp/build.sh
COPY build_files/identity.sh /tmp/identity.sh
COPY build_files/check-fonts.sh /tmp/check-fonts.sh

RUN --mount=type=cache,dst=/var/cache/libdnf5,sharing=locked \
    TARGETARCH="${TARGETARCH}" bash /tmp/build.sh && \
    rm -f /tmp/build.sh /tmp/identity.sh /tmp/check-fonts.sh

RUN bootc container lint --fatal-warnings
