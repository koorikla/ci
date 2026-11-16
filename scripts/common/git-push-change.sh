#!/usr/bin/env bash
# Commit the given paths (if they changed) and push to BRANCH, rebasing and
# retrying when the branch moved meanwhile. Needs a checkout whose `origin`
# can be pushed to (actions/checkout with persist-credentials, or a credential
# helper in-cluster).
#
# Env in:
#   PATHS           space-separated paths to commit (required)
#   MESSAGE         commit message (required)
#   BRANCH          branch to push to (required)
#   PUSH            true/false, default true (false = commit locally, print diff)
#   GIT_USER_NAME   default github-actions[bot]
#   GIT_USER_EMAIL  default 41898282+github-actions[bot]@users.noreply.github.com
#   RETRIES         default 3
# Outputs:
#   pushed      true when a commit was pushed
#   commit_sha  the commit created ('' when nothing changed)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_env PATHS MESSAGE BRANCH
require_cmd git

# shellcheck disable=SC2086
set -- ${PATHS}
if git diff --quiet -- "$@"; then
  log "no changes in ${PATHS}; nothing to commit"
  emit_output pushed false
  emit_output commit_sha ""
  exit 0
fi

git -c color.ui=never diff --stat -- "$@" >&2
git config user.name "${GIT_USER_NAME:-github-actions[bot]}"
git config user.email "${GIT_USER_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
git add -- "$@"
git commit -q -m "${MESSAGE}"
sha="$(git rev-parse HEAD)"

if ! is_true "${PUSH:-true}"; then
  log "PUSH=false: committed ${sha} locally, not pushing"
  git -c color.ui=never show --stat HEAD >&2
  emit_output pushed false
  emit_output commit_sha "${sha}"
  exit 0
fi

n="${RETRIES:-3}"
i=1
while :; do
  if git push -q origin "HEAD:refs/heads/${BRANCH}"; then
    break
  fi
  [[ "${i}" -lt "${n}" ]] || die "push to ${BRANCH} failed after ${n} attempts"
  warn "push rejected (attempt ${i}/${n}); rebasing on origin/${BRANCH}"
  git fetch -q origin "${BRANCH}"
  git rebase -q "FETCH_HEAD"
  i=$((i + 1))
  sleep "${i}"
done
sha="$(git rev-parse HEAD)"
log "pushed ${sha} to ${BRANCH}"
emit_output pushed true
emit_output commit_sha "${sha}"
