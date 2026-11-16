#!/usr/bin/env bash
# Detect the package manager and Node.js version file of a Node.js project
# (Express, Fastify, NestJS, Nuxt, SvelteKit, Remix, ...).
#
# Package manager: package.json "packageManager" (corepack, e.g. pnpm@10.20.0)
# wins, then the lockfile (pnpm-lock.yaml, yarn.lock, package-lock.json /
# npm-shrinkwrap.json), else npm.
#
# Env in:
#   WORKDIR  project directory, default .
# Outputs:
#   pm                 npm | pnpm | yarn
#   pm_spec            packageManager value ('' when unset), e.g. pnpm@10.20.0
#   lockfile           path relative to WORKDIR ('' when none)
#   node_version_file  .nvmrc | .node-version | .tool-versions | package.json
#                      (relative to the repository root, i.e. prefixed with WORKDIR)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/lib.sh
source "${SCRIPT_DIR}/../common/lib.sh"

require_cmd jq
wd="${WORKDIR:-.}"
[[ -f "${wd}/package.json" ]] || die "${wd}/package.json not found"

spec="$(jq -r '.packageManager // empty' "${wd}/package.json")"
pm=""
case "${spec}" in
  pnpm@* | pnpm) pm=pnpm ;;
  yarn@* | yarn) pm=yarn ;;
  npm@* | npm) pm=npm ;;
  "") ;;
  *) die "unsupported packageManager '${spec}' in package.json" ;;
esac

lockfile=""
if [[ -f "${wd}/pnpm-lock.yaml" ]]; then
  lockfile="pnpm-lock.yaml"
  pm="${pm:-pnpm}"
elif [[ -f "${wd}/yarn.lock" ]]; then
  lockfile="yarn.lock"
  pm="${pm:-yarn}"
elif [[ -f "${wd}/package-lock.json" ]]; then
  lockfile="package-lock.json"
elif [[ -f "${wd}/npm-shrinkwrap.json" ]]; then
  lockfile="npm-shrinkwrap.json"
fi
pm="${pm:-npm}"
if [[ -z "${lockfile}" ]]; then
  warn "no lockfile in ${wd}; installs are not reproducible (frozen install will fail for pnpm/yarn)"
fi

vfile="package.json"
for f in .nvmrc .node-version .tool-versions; do
  if [[ -f "${wd}/${f}" ]]; then
    if [[ "$f" != ".tool-versions" ]] || grep -Eq '^(nodejs|node)[[:space:]]' "${wd}/${f}"; then
      vfile="$f"
      break
    fi
  fi
done

emit_output pm "${pm}"
emit_output pm_spec "${spec}"
emit_output lockfile "${lockfile}"
emit_output node_version_file "${wd%/}/${vfile}"
log "package manager=${pm}${spec:+ (${spec})} lockfile=${lockfile:-none} node version file=${vfile}"
