#!/usr/bin/env bash
# Make the project's package manager available through corepack (pnpm, yarn;
# the version pinned in package.json "packageManager" when set) and report its
# download cache directory (for CI caching).
#
# Corepack ships with Node.js <= 24; on newer Node.js it is installed from npm.
#
# Env in:
#   WORKDIR  project directory, default .
#   PM       npm | pnpm | yarn (default: scripts/node/detect.sh)
# Outputs:
#   cache_dir  package-manager download cache/store directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/lib.sh
source "${SCRIPT_DIR}/../common/lib.sh"

require_cmd node npm
pm="${PM:-}"
if [[ -z "${pm}" ]]; then
  tmpd="$(mktemp -d "${TMPDIR:-/tmp}/node-detect.XXXXXX")"
  CI_OUT_DIR="${tmpd}" GITHUB_OUTPUT="" bash "${SCRIPT_DIR}/detect.sh"
  pm="$(cat "${tmpd}/pm")"
  rm -rf "${tmpd}"
fi
cd "${WORKDIR:-.}"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

if [[ "${pm}" != "npm" ]]; then
  if ! command -v corepack >/dev/null 2>&1; then
    log "corepack not bundled with node $(node --version); installing it from npm"
    npm install --global --no-audit --no-fund corepack
  fi
  log "corepack enable ${pm}"
  if ! corepack enable "${pm}" 2>/dev/null; then
    # Global node install not writable (e.g. non-root toolchain image): shims in a user dir.
    d="${HOME:-/tmp}/.local/corepack-bin"
    mkdir -p "${d}"
    corepack enable --install-directory "${d}" "${pm}"
    PATH="${d}:${PATH}"
    export PATH
    if [[ -n "${GITHUB_PATH:-}" ]]; then
      printf '%s\n' "${d}" >>"${GITHUB_PATH}"
    fi
  fi
fi

log "${pm} $("${pm}" --version)"
case "${pm}" in
  npm) cache_dir="$(npm config get cache)" ;;
  pnpm) cache_dir="$(pnpm store path --silent)" ;;
  yarn)
    if [[ -f .yarnrc.yml ]] || [[ "$(yarn --version)" != 1.* ]]; then
      cache_dir="$(yarn config get cacheFolder)"
    else
      cache_dir="$(yarn cache dir)"
    fi
    ;;
  *) die "unsupported package manager ${pm}" ;;
esac
emit_output cache_dir "${cache_dir}"
log "cache dir ${cache_dir}"
