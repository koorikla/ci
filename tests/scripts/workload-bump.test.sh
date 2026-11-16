#!/usr/bin/env bash
# Unit tests for scripts/common/workload-bump.sh and git-push-change.sh
# (bash 3.2 compatible; run by selftest.yaml and locally:
#   bash tests/scripts/workload-bump.test.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="${ROOT}/scripts/common"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/wb-test.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT
fails=0

ok() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  fails=$((fails + 1))
}

d64="$(printf '%064d' 0 | tr 0 a)"
cp "${ROOT}/fixtures/openchoreo/workload.yaml" "${tmp}/w.yaml"

# 1. image + commit rewritten in place, everything else untouched.
CI_OUT_DIR="${tmp}/out" WORKLOAD_FILE="${tmp}/w.yaml" IMAGE="ghcr.io/koorikla/app:abc1234" \
  DIGEST="sha256:${d64}" COMMIT="abc1234def" bash "${S}/workload-bump.sh" 2>/dev/null
if grep -q "^    image: ghcr.io/koorikla/app:abc1234@sha256:${d64}\$" "${tmp}/w.yaml" &&
  grep -q '^    commit: "abc1234def"$' "${tmp}/w.yaml" &&
  [[ "$(grep -cvxFf "${ROOT}/fixtures/openchoreo/workload.yaml" "${tmp}/w.yaml")" == 2 ]] &&
  [[ "$(wc -l <"${tmp}/w.yaml")" == "$(wc -l <"${ROOT}/fixtures/openchoreo/workload.yaml")" ]] &&
  [[ "$(cat "${tmp}/out/changed")" == true ]]; then
  ok "bumps image and commit only"
else
  fail "bumps image and commit only"
  diff "${ROOT}/fixtures/openchoreo/workload.yaml" "${tmp}/w.yaml" || true
fi

# 2. idempotent.
CI_OUT_DIR="${tmp}/out" WORKLOAD_FILE="${tmp}/w.yaml" IMAGE="ghcr.io/koorikla/app:abc1234@sha256:${d64}" \
  COMMIT="abc1234def" bash "${S}/workload-bump.sh" 2>/dev/null
if [[ "$(cat "${tmp}/out/changed")" == false ]]; then ok "idempotent"; else fail "idempotent"; fi

# 3. rejects references without a tag or digest, and junk commits.
for bad in "ghcr.io/koorikla/app@sha256:${d64}" "ghcr.io/koorikla/app:tag" "ghcr.io/koorikla/app:tag@sha256:short"; do
  if WORKLOAD_FILE="${tmp}/w.yaml" IMAGE="${bad}" bash "${S}/workload-bump.sh" 2>/dev/null; then
    fail "rejects ${bad}"
  else
    ok "rejects ${bad}"
  fi
done
if WORKLOAD_FILE="${tmp}/w.yaml" IMAGE="r:t@sha256:${d64}" COMMIT='x"; rm -rf /' bash "${S}/workload-bump.sh" 2>/dev/null; then
  fail "rejects non-hex COMMIT"
else
  ok "rejects non-hex COMMIT"
fi

# 4. picks container.image, not an earlier image: key elsewhere; registry with port.
cat >"${tmp}/w2.yaml" <<'EOF'
metadata:
  annotations:
    image: keep-me
spec:
  container:
    # comment
    env: []
    image: old
EOF
WORKLOAD_FILE="${tmp}/w2.yaml" IMAGE="harbor.local:9443/apps/x:t1@sha256:${d64}" \
  bash "${S}/workload-bump.sh" 2>/dev/null
if grep -q '^    image: keep-me$' "${tmp}/w2.yaml" && grep -q "^    image: harbor.local:9443/apps/x:t1@sha256:${d64}\$" "${tmp}/w2.yaml"; then
  ok "targets spec.container.image (registry with port)"
else
  fail "targets spec.container.image (registry with port)"
  cat "${tmp}/w2.yaml"
fi

# 5. git-push-change.sh: commits only when changed, PUSH=false never pushes.
repo="${tmp}/repo"
git init -q "${repo}"
cp "${ROOT}/fixtures/openchoreo/workload.yaml" "${repo}/w.yaml"
git -C "${repo}" add w.yaml
git -C "${repo}" -c user.name=t -c user.email=t@t commit -q -m init
(
  cd "${repo}"
  CI_OUT_DIR="${tmp}/out2" PATHS=w.yaml MESSAGE=noop BRANCH=main PUSH=false bash "${S}/git-push-change.sh" 2>/dev/null
)
if [[ "$(git -C "${repo}" rev-list --count HEAD)" == 1 && "$(cat "${tmp}/out2/pushed")" == false ]]; then
  ok "no commit without changes"
else
  fail "no commit without changes"
fi
(
  cd "${repo}"
  WORKLOAD_FILE=w.yaml IMAGE="r/x:t@sha256:${d64}" bash "${S}/workload-bump.sh" 2>/dev/null
  CI_OUT_DIR="${tmp}/out2" PATHS=w.yaml MESSAGE="chore: bump [skip ci]" BRANCH=main PUSH=false \
    bash "${S}/git-push-change.sh" 2>/dev/null
)
if [[ "$(git -C "${repo}" rev-list --count HEAD)" == 2 && "$(git -C "${repo}" log -1 --format=%s)" == "chore: bump [skip ci]" &&
  -n "$(cat "${tmp}/out2/commit_sha")" ]]; then
  ok "commits the change locally with PUSH=false"
else
  fail "commits the change locally with PUSH=false"
fi

[[ "${fails}" -eq 0 ]] || {
  printf '%s test(s) failed\n' "${fails}"
  exit 1
}
printf 'all workload-bump tests passed\n'
