# syntax=docker/dockerfile:1
# Python (uv) service on distroless Python, non-root. Builds on the target
# platform (native runner per arch) because wheels may be arch-specific.
# Runtime dependencies + the project wheel are installed into /app/site-packages
# (no virtualenv: distroless python is /usr/bin/python3.13, so a venv built
# elsewhere would point at the wrong interpreter). Keep PYTHON_IMAGE on the same
# minor version as the distroless runtime (Debian 13 = Python 3.13).
ARG PYTHON_IMAGE=docker.io/library/python:3.13.18-slim-trixie@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90

FROM ghcr.io/astral-sh/uv:0.13.8@sha256:5cc1805e2426484abca4ad46ea783bab281fdb225fd82d8ce6d66a81254bac85 AS uv

FROM ${PYTHON_IMAGE} AS build
COPY --from=uv /uv /usr/local/bin/uv
ENV UV_PYTHON_DOWNLOADS=never UV_LINK_MODE=copy UV_NO_PROGRESS=1
WORKDIR /src
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv export --frozen --no-dev --no-emit-workspace --format requirements-txt --output-file /tmp/requirements.txt \
 && if grep -Eq '^[A-Za-z0-9]' /tmp/requirements.txt; then \
      uv pip install --python /usr/local/bin/python3 --target /app/site-packages \
        --require-hashes --compile-bytecode -r /tmp/requirements.txt; \
    fi
COPY . .
RUN --mount=type=cache,target=/root/.cache/uv \
    uv build --wheel --out-dir /tmp/dist \
 && uv pip install --python /usr/local/bin/python3 --target /app/site-packages \
      --no-deps --compile-bytecode /tmp/dist/*.whl

FROM gcr.io/distroless/python3-debian13:nonroot@sha256:6c4cb3bfa4b555429dd19541796a6ba6b30c84675b460bd0bd5072f7d5bdae71
COPY --from=build /app/site-packages /app/site-packages
ARG VERSION=dev
ENV PYTHONPATH=/app/site-packages PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 VERSION=${VERSION}
USER nonroot:nonroot
EXPOSE 8080
# ENTRYPOINT is /usr/bin/python3.13
CMD ["-m", "ci_selftest_python"]
