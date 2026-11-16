#!/usr/bin/env bash
# Point an OpenChoreo Workload at a new image: rewrite spec.container.image
# to <repo>:<tag>@sha256:<digest> (production admission accepts only digest
# references; the tag keeps it readable) and spec.source.commit to the built
# commit. Comments and the rest of the file are left untouched (line-based
# edit, no YAML round-trip). Commit/push is done by git-push-change.sh.
#
# Env in:
#   WORKLOAD_FILE  default deploy/openchoreo/workload.yaml
#   IMAGE          <repo>:<tag> or <repo>:<tag>@sha256:<digest>   (required)
#   DIGEST         sha256:<64 hex>, appended to IMAGE when IMAGE has no digest
#   COMMIT         optional source commit SHA written to the first `commit:` key
# Outputs:
#   image    the full reference written
#   changed  true when the file changed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_env IMAGE
require_cmd awk cmp mktemp

file="${WORKLOAD_FILE:-deploy/openchoreo/workload.yaml}"
[[ -f "${file}" ]] || die "workload file ${file} not found"

image="${IMAGE:?}"
case "${image}" in
  *@*) ;;
  *)
    [[ -n "${DIGEST:-}" ]] || die "IMAGE has no digest and DIGEST is empty"
    image="${image}@${DIGEST}"
    ;;
esac
# <repo>:<tag>@sha256:<64 hex>, no whitespace; the tag part is mandatory.
if ! printf '%s' "${image}" | grep -Eq '^[^[:space:]@]+:[^[:space:]@/]+@sha256:[0-9a-f]{64}$'; then
  die "IMAGE must be <repo>:<tag>@sha256:<64 hex>, got '${image}'"
fi
commit="${COMMIT:-}"
if [[ -n "${commit}" ]] && ! printf '%s' "${commit}" | grep -Eq '^[0-9a-f]{7,64}$'; then
  die "COMMIT must be a hex SHA, got '${commit}'"
fi

tmp="$(mktemp "${TMPDIR:-/tmp}/workload.XXXXXX")"
trap 'rm -f "${tmp}"' EXIT

# image: the first `image:` key nested under a `container:` mapping (falls back
# to the first `image:` key anywhere). commit: the first `commit:` key.
rc=0
awk -v img="${image}" -v commit="${commit}" '
  function ind(s) { match(s, /^[ ]*/); return RLENGTH }
  { lines[NR] = $0 }
  END {
    target = 0; in_c = 0
    for (i = 1; i <= NR; i++) {
      l = lines[i]
      if (l ~ /^[ ]*container:[ ]*(#.*)?$/) { in_c = 1; c_ind = ind(l); continue }
      if (!in_c || l ~ /^[ ]*(#.*)?$/) continue
      if (ind(l) <= c_ind) { in_c = 0; continue }
      if (l ~ /^[ ]*image:/) { target = i; break }
    }
    if (!target) for (i = 1; i <= NR; i++) if (lines[i] ~ /^[ ]*image:/) { target = i; break }
    if (!target) exit 3
    done_commit = 0
    for (i = 1; i <= NR; i++) {
      l = lines[i]
      if (i == target) {
        match(l, /^[ ]*image:/); l = substr(l, 1, RLENGTH) " " img
      } else if (commit != "" && !done_commit && l ~ /^[ ]*commit:/) {
        match(l, /^[ ]*commit:/); l = substr(l, 1, RLENGTH) " \"" commit "\""; done_commit = 1
      }
      print l
    }
    if (commit != "" && !done_commit) exit 4
  }' "${file}" >"${tmp}" || rc=$?

case "${rc}" in
  0) ;;
  3) die "no image: key found in ${file}" ;;
  4) warn "COMMIT set but no commit: key in ${file}; only the image was bumped" ;;
  *) die "awk failed (${rc}) editing ${file}" ;;
esac

changed=false
if ! cmp -s "${tmp}" "${file}"; then
  cat "${tmp}" >"${file}"
  changed=true
fi

emit_output image "${image}"
emit_output changed "${changed}"
log "${file}: image=${image}${commit:+ commit=${commit}} changed=${changed}"
step_summary "- Workload \`${file}\`: \`${image}\` (changed: ${changed})"
