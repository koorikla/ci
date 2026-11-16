# syntax=docker/dockerfile:1
# Node.js service (Express, Fastify, NestJS, Nuxt, SvelteKit adapter-node,
# Remix, ...) on distroless Node.js, non-root. Builds on the target platform
# (native runner per arch) because node_modules may contain native addons.
#
# Build args:
#   BUILD_SCRIPT  package.json script that builds the app (default build; skipped
#                 when the script does not exist)
#   START_ENTRY   JS file started by node, relative to /app, e.g.
#                 dist/main.js (NestJS), dist/server.js (Express/Fastify + tsc),
#                 .output/server/index.mjs (Nuxt), build/index.js (SvelteKit),
#                 node_modules/@remix-run/serve/dist/cli.js (Remix, START_ARGS=build/server/index.js)
#   START_ARGS    optional space-separated arguments for START_ENTRY
# The package manager comes from package.json "packageManager" / the lockfile
# (corepack for pnpm and yarn). Dev dependencies are pruned after the build.
ARG NODE_IMAGE=docker.io/library/node:24-trixie-slim@sha256:af02d57b57719b9657a45199a79264a9437940cd55b3c7b3fc99615654f124a0

FROM ${NODE_IMAGE} AS build
WORKDIR /app
ENV CI=true COREPACK_ENABLE_DOWNLOAD_PROMPT=0
COPY package.json package-lock.json* npm-shrinkwrap.json* pnpm-lock.yaml* pnpm-workspace.yaml* yarn.lock* .npmrc* .yarnrc.yml* ./
RUN --mount=type=cache,target=/root/.npm \
    --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/root/.local/share/pnpm/store \
    if [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm install --frozen-lockfile; \
    elif [ -f yarn.lock ]; then corepack enable yarn && if [ -f .yarnrc.yml ]; then yarn install --immutable; else yarn install --frozen-lockfile; fi; \
    else npm ci --no-audit --no-fund; fi
COPY . .
ARG VERSION=dev
ARG BUILD_SCRIPT=build
ENV VERSION=${VERSION}
RUN --mount=type=cache,target=/root/.npm \
    --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/root/.local/share/pnpm/store \
    if [ -f pnpm-lock.yaml ]; then pm=pnpm; elif [ -f yarn.lock ]; then pm=yarn; else pm=npm; fi; \
    if node -e "process.exit(require('./package.json').scripts?.[process.argv[1]] ? 0 : 1)" "${BUILD_SCRIPT}"; then \
      "$pm" run "${BUILD_SCRIPT}"; \
    fi; \
    case "$pm" in \
      pnpm) pnpm prune --prod --ignore-scripts ;; \
      yarn) if [ -f .yarnrc.yml ]; then yarn workspaces focus --all --production; else yarn install --frozen-lockfile --production --ignore-scripts; fi ;; \
      npm) npm prune --omit=dev --no-audit --no-fund ;; \
    esac

# Starts START_ENTRY with node: exec-form CMD cannot expand build args.
COPY <<'EOF' /koorikla-start.mjs
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const entry = process.env.START_ENTRY;
if (!entry) {
  console.error("START_ENTRY is not set");
  process.exit(64);
}
const args = (process.env.START_ARGS ?? "").split(" ").filter(Boolean);
process.argv.splice(1, process.argv.length - 1, resolve("/app", entry), ...args);
await import(pathToFileURL(resolve("/app", entry)).href);
EOF

# Runtime: distroless Node.js, non-root (uid 65532), no shell or package manager.
FROM gcr.io/distroless/nodejs24-debian13:nonroot@sha256:6abfcb367ebc291572c774c1592a986be2ab26a2486f73093401327495a5962a
WORKDIR /app
ARG VERSION=dev
ARG START_ENTRY=dist/server.js
ARG START_ARGS=
ENV NODE_ENV=production PORT=8080 HOST=0.0.0.0 VERSION=${VERSION} \
    START_ENTRY=${START_ENTRY} START_ARGS=${START_ARGS}
COPY --from=build /koorikla-start.mjs /koorikla-start.mjs
COPY --from=build /app /app
USER nonroot:nonroot
EXPOSE 8080
CMD ["/koorikla-start.mjs"]
