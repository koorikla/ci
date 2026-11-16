# syntax=docker/dockerfile:1
# Rust service: static musl binary on distroless static, non-root.
# Builds on the target platform (koorikla/ci builds each arch on a native
# runner), so no cross toolchain is needed; the Alpine Rust image targets musl,
# which links statically by default. rust-toolchain.toml is honoured (rustup
# installs the pinned channel if it differs from the image): keep RUST_IMAGE on
# the same version to skip that download.
# BIN_NAME selects the binary when the package has several (default: the only one).
ARG RUST_IMAGE=docker.io/library/rust:1.100.0-alpine3.24@sha256:de1e0058543a81ed7b046629167db587c67a94bdf37cce14eb27f0ec83baaffb

FROM ${RUST_IMAGE} AS build
RUN apk add --no-cache musl-dev
WORKDIR /src
COPY . .
ARG VERSION=dev
ARG BIN_NAME=
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    set -eu; \
    if [ -f rust-toolchain.toml ] || [ -f rust-toolchain ]; then rustup toolchain install; fi; \
    cargo build --release --locked --bins --message-format=json-render-diagnostics > /tmp/build.json; \
    bins="$(grep -o '"executable":"[^"]*"' /tmp/build.json | cut -d'"' -f4 | sort -u)"; \
    if [ -n "${BIN_NAME}" ]; then bins="$(printf '%s\n' "$bins" | grep "/${BIN_NAME}\$" || true)"; fi; \
    [ "$(printf '%s\n' "$bins" | grep -c .)" = 1 ] || { echo "expected one binary, got: $bins (set BIN_NAME)"; exit 1; }; \
    install -D -m 0755 "$bins" /out/app

FROM gcr.io/distroless/static-debian13:nonroot@sha256:aafe993665bf6200db38a02c11a9351e782a84b6a45e7f33b6695638c88e3931
COPY --from=build /out/app /app
ARG VERSION=dev
ENV VERSION=${VERSION}
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/app"]
