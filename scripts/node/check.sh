#!/usr/bin/env bash
# Node.js checks (Express, Fastify, NestJS, Nuxt, SvelteKit, Remix, ...):
# lockfile-frozen install, then the project's own scripts when defined:
# lint, typecheck (or tsc --noEmit), test, build; dependency audit of
# production dependencies.
#
# Env in:
#   WORKDIR           project directory, default .
#   PM                npm | pnpm | yarn (default: scripts/node/detect.sh)
#   RUN_LINT          default true  (LINT_SCRIPT, default `lint`, if defined)
#   RUN_TYPECHECK     default true  (TYPECHECK_SCRIPT, default `typecheck`, if
#                     defined, else tsc --noEmit when tsconfig.json + typescript)
#   RUN_TEST          default true  (TEST_SCRIPT, default `test`, if defined)
#   RUN_BUILD         default true  (BUILD_SCRIPT, default `build`, if defined)
#   RUN_AUDIT         default true
#   AUDIT_LEVEL       low | moderate | high | critical, default critical
#   LINT_SCRIPT TYPECHECK_SCRIPT TEST_SCRIPT BUILD_SCRIPT  script name overrides
# Files out: whatever the build script writes (dist/, build/, .output/, ...)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/lib.sh
source "${SCRIPT_DIR}/../common/lib.sh"

require_cmd node npm jq
wd="${WORKDIR:-.}"
pm="${PM:-}"
if [[ -z "${pm}" ]]; then
  tmpd="$(mktemp -d "${TMPDIR:-/tmp}/node-detect.XXXXXX")"
  CI_OUT_DIR="${tmpd}" GITHUB_OUTPUT="" bash "${SCRIPT_DIR}/detect.sh"
  pm="$(cat "${tmpd}/pm")"
  rm -rf "${tmpd}"
fi
if ! command -v "${pm}" >/dev/null 2>&1; then
  WORKDIR="${wd}" PM="${pm}" CI_OUT_DIR="" GITHUB_OUTPUT="" bash "${SCRIPT_DIR}/setup-pm.sh"
  PATH="${HOME:-/tmp}/.local/corepack-bin:${PATH}"
  export PATH
fi
require_cmd "${pm}"
cd "${wd}"
export CI=true COREPACK_ENABLE_DOWNLOAD_PROMPT=0

yarn_berry=false
if [[ "${pm}" == "yarn" ]] && { [[ -f .yarnrc.yml ]] || [[ "$(yarn --version)" != 1.* ]]; }; then
  yarn_berry=true
fi

has_script() {
  [[ -n "$(jq -r --arg s "$1" '.scripts[$s] // empty' package.json)" ]]
}

run_script() {
  log "${pm} run $1"
  "${pm}" run "$1"
}

# pm_exec BIN ARGS... - run a locally installed binary.
pm_exec() {
  case "${pm}" in
    npm) npx --no-install "$@" ;;
    *) "${pm}" exec "$@" ;;
  esac
}

log "install (${pm}, frozen lockfile)"
case "${pm}" in
  npm)
    if [[ -f package-lock.json || -f npm-shrinkwrap.json ]]; then
      npm ci --no-audit --no-fund
    else
      warn "no package-lock.json: npm install (not reproducible)"
      npm install --no-audit --no-fund
    fi
    ;;
  pnpm) pnpm install --frozen-lockfile ;;
  yarn)
    if [[ "${yarn_berry}" == "true" ]]; then
      yarn install --immutable
    else
      yarn install --frozen-lockfile
    fi
    ;;
  *) die "unsupported package manager ${pm}" ;;
esac

if is_true "${RUN_LINT:-true}"; then
  if has_script "${LINT_SCRIPT:-lint}"; then
    run_script "${LINT_SCRIPT:-lint}"
  else
    warn "no '${LINT_SCRIPT:-lint}' script; skipping lint"
  fi
fi

if is_true "${RUN_TYPECHECK:-true}"; then
  if has_script "${TYPECHECK_SCRIPT:-typecheck}"; then
    run_script "${TYPECHECK_SCRIPT:-typecheck}"
  elif [[ -f tsconfig.json ]] && [[ -n "$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | .typescript // empty' package.json)" ]]; then
    log "tsc --noEmit"
    pm_exec tsc --noEmit
  fi
fi

if is_true "${RUN_TEST:-true}"; then
  if has_script "${TEST_SCRIPT:-test}"; then
    run_script "${TEST_SCRIPT:-test}"
  else
    warn "no '${TEST_SCRIPT:-test}' script; skipping tests"
  fi
fi

if is_true "${RUN_BUILD:-true}"; then
  if has_script "${BUILD_SCRIPT:-build}"; then
    run_script "${BUILD_SCRIPT:-build}"
  else
    log "no '${BUILD_SCRIPT:-build}' script; nothing to build"
  fi
fi

if is_true "${RUN_AUDIT:-true}"; then
  level="${AUDIT_LEVEL:-critical}"
  log "dependency audit (${pm}, production deps, level ${level})"
  case "${pm}" in
    npm) npm audit --omit=dev --audit-level="${level}" ;;
    pnpm) pnpm audit --prod --audit-level "${level}" ;;
    yarn)
      if [[ "${yarn_berry}" == "true" ]]; then
        yarn npm audit --environment production --recursive --severity "${level}"
      else
        yarn audit --groups dependencies --level "${level}"
      fi
      ;;
  esac
fi
