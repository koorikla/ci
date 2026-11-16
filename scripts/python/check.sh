#!/usr/bin/env bash
# Python (uv) checks: lockfile up to date, uv sync --frozen, ruff check +
# ruff format --check, pytest (+ coverage with pytest-cov), pip-audit of the
# exported runtime requirements.
#
# Env in:
#   WORKDIR         project directory (pyproject.toml + uv.lock), default .
#   UV_SYNC_ARGS    default "--frozen --all-extras" (dev group is synced by default)
#   RUN_LINT        default true  (ruff check + ruff format --check; the locked ruff
#                   when it is a dependency, else `uvx ruff@RUFF_VERSION`)
#   RUFF_VERSION    default latest (only when ruff is not locked)
#   RUN_TYPECHECK   default auto  (mypy when it is locked; true forces, false skips)
#   RUN_TEST        default true  (pytest when locked or tests/ exists)
#   TEST_ARGS       extra pytest arguments
#   COVERAGE        default true  (--cov when pytest-cov is locked; coverage.xml)
#   RUN_AUDIT       default true  (pip-audit on `uv export --no-dev` requirements)
#   PIP_AUDIT_VERSION default latest
#   AUDIT_IGNORE    space-separated vulnerability IDs to ignore (accepted risks)
#   CI_OUT_DIR      output dir, default ./.ci-out
# Files out:
#   $WORKDIR/coverage.xml, $CI_OUT_DIR/requirements-audit.txt
# Outputs: coverage (percent, when measured)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/lib.sh
source "${SCRIPT_DIR}/../common/lib.sh"

require_cmd uv
out="$(out_dir)"
case "${out}" in /*) ;; *) out="$(pwd)/${out}" ;; esac
cd "${WORKDIR:-.}"
[[ -f pyproject.toml ]] || die "pyproject.toml not found in ${WORKDIR:-.}"
[[ -f uv.lock ]] || die "uv.lock not found in ${WORKDIR:-.} (run \`uv lock\` and commit it)"

export UV_NO_PROGRESS=1 PYTHONDONTWRITEBYTECODE=1

# locked NAME - true when NAME is a package in uv.lock.
locked() {
  grep -Eq "^name = \"$1\"$" uv.lock
}

log "uv lock --check (uv.lock matches pyproject.toml)"
uv lock --check

# shellcheck disable=SC2086
log "uv sync ${UV_SYNC_ARGS:---frozen --all-extras}"
# shellcheck disable=SC2086
uv sync ${UV_SYNC_ARGS:---frozen --all-extras}
uv run --frozen python --version >&2

if is_true "${RUN_LINT:-true}"; then
  if locked ruff; then
    set -- uv run --frozen --no-sync ruff
  else
    set -- uvx "ruff@${RUFF_VERSION:-latest}"
  fi
  log "ruff check"
  "$@" check --output-format=full .
  log "ruff format --check"
  "$@" format --check --diff .
fi

tc="${RUN_TYPECHECK:-auto}"
if [[ "${tc}" == "auto" ]]; then
  if locked mypy; then tc=true; else tc=false; fi
fi
if is_true "${tc}"; then
  log "mypy"
  uv run --frozen --no-sync mypy .
fi

if is_true "${RUN_TEST:-true}"; then
  if locked pytest || [[ -d tests ]]; then
    set -- --no-sync pytest
    if ! locked pytest; then
      warn "pytest is not locked; running it ad hoc (uv run --with pytest)"
      set -- --with pytest pytest
    fi
    if is_true "${COVERAGE:-true}" && locked pytest-cov; then
      set -- "$@" --cov --cov-report=term --cov-report=xml:coverage.xml
    fi
    # shellcheck disable=SC2086
    log "pytest ${TEST_ARGS:-}"
    # shellcheck disable=SC2086
    uv run --frozen "$@" ${TEST_ARGS:-}
    if [[ -f coverage.xml ]]; then
      pct="$(awk -F'line-rate="' 'NR <= 3 && /<coverage / { split($2, a, "\""); printf "%.1f%%", a[1] * 100; exit }' coverage.xml)"
      if [[ -n "${pct}" ]]; then
        log "coverage: ${pct}"
        emit_output coverage "${pct}"
        step_summary "- Python coverage (\`${WORKDIR:-.}\`): ${pct}"
      fi
    fi
  else
    warn "no pytest in uv.lock and no tests/ directory; skipping tests"
  fi
fi

if is_true "${RUN_AUDIT:-true}"; then
  req="${out}/requirements-audit.txt"
  log "uv export --no-dev (runtime requirements) -> ${req}"
  uv export --frozen --no-dev --all-extras --no-emit-workspace \
    --format requirements-txt --output-file "${req}" >/dev/null
  if grep -Eq '^[A-Za-z0-9]' "${req}"; then
    set -- -r "${req}" --require-hashes --disable-pip --progress-spinner off --desc on
    for id in ${AUDIT_IGNORE:-}; do
      set -- "$@" --ignore-vuln "${id}"
    done
    log "pip-audit (runtime dependencies)"
    uvx "pip-audit@${PIP_AUDIT_VERSION:-latest}" "$@"
  else
    log "no runtime dependencies; skipping pip-audit"
  fi
fi
