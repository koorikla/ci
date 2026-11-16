#!/usr/bin/env bash
# Rust checks: pinned toolchain (rust-toolchain.toml), cargo fmt --check,
# clippy -D warnings, tests (cargo-nextest when installed, else cargo test),
# cargo-deny (advisories, bans, licenses, sources) and cargo-audit.
#
# Env in:
#   WORKDIR        crate / workspace directory, default .
#   RUN_FMT        default true
#   RUN_CLIPPY     default true
#   CLIPPY_ARGS    default "--all-targets --all-features --locked -- -D warnings"
#   RUN_TEST       default true
#   TEST_RUNNER    auto | nextest | cargo, default auto (nextest when installed)
#   TEST_ARGS      extra test arguments (default --workspace --all-features --locked)
#   RUN_DENY       default true (cargo-deny; licenses only checked with a deny.toml)
#   RUN_AUDIT      default true (cargo-audit)
#   INSTALL_TOOLS  default true: `cargo install --locked` missing cargo-deny /
#                  cargo-audit (slow; CI preinstalls prebuilt binaries)
# Files out: target/ (build cache)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/lib.sh
source "${SCRIPT_DIR}/../common/lib.sh"

require_cmd cargo
cd "${WORKDIR:-.}"
[[ -f Cargo.toml ]] || die "Cargo.toml not found in ${WORKDIR:-.}"
[[ -f Cargo.lock ]] || die "Cargo.lock not found in ${WORKDIR:-.}: commit it for binaries (--locked builds)"
export CARGO_TERM_COLOR="${CARGO_TERM_COLOR:-always}"

if [[ -f rust-toolchain.toml || -f rust-toolchain ]]; then
  if command -v rustup >/dev/null 2>&1; then
    # rustup >= 1.28 installs the toolchain (and its components) named by the file.
    log "rustup toolchain install (rust-toolchain.toml)"
    rustup toolchain install
  else
    warn "rust-toolchain.toml present but rustup missing; using $(cargo --version)"
  fi
else
  warn "no rust-toolchain.toml: the toolchain is not pinned"
fi
log "$(cargo --version); $(rustc --version)"

# ensure_tool BIN CRATE - true when BIN is available (installing it if allowed).
ensure_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  if is_true "${INSTALL_TOOLS:-true}"; then
    log "cargo install --locked $2"
    cargo install --locked "$2"
    return 0
  fi
  return 1
}

if is_true "${RUN_FMT:-true}"; then
  log "cargo fmt --all --check"
  cargo fmt --all --check
fi

if is_true "${RUN_CLIPPY:-true}"; then
  # shellcheck disable=SC2086
  log "cargo clippy ${CLIPPY_ARGS:---all-targets --all-features --locked -- -D warnings}"
  # shellcheck disable=SC2086
  cargo clippy ${CLIPPY_ARGS:---all-targets --all-features --locked -- -D warnings}
fi

if is_true "${RUN_TEST:-true}"; then
  runner="${TEST_RUNNER:-auto}"
  if [[ "${runner}" == "auto" ]]; then
    if cargo nextest --version >/dev/null 2>&1; then runner=nextest; else runner=cargo; fi
  fi
  targs="${TEST_ARGS:---workspace --all-features --locked}"
  case "${runner}" in
    nextest)
      log "cargo nextest run ${targs}"
      # shellcheck disable=SC2086
      cargo nextest run ${targs} --no-tests=warn
      # nextest does not run doctests; only library targets have them.
      meta="$(cargo metadata --no-deps --format-version 1 --locked)"
      case "${meta}" in
        *'"doctest":true'*)
          log "cargo test --doc"
          # shellcheck disable=SC2086
          cargo test --doc ${targs}
          ;;
      esac
      ;;
    cargo)
      log "cargo test ${targs}"
      # shellcheck disable=SC2086
      cargo test ${targs}
      ;;
    *) die "unknown TEST_RUNNER ${runner}" ;;
  esac
fi

if is_true "${RUN_DENY:-true}"; then
  ensure_tool cargo-deny cargo-deny || die "cargo-deny not installed (INSTALL_TOOLS=false)"
  if [[ -f deny.toml || -f .cargo/deny.toml ]]; then
    log "cargo deny check (advisories bans licenses sources)"
    cargo deny --locked check
  else
    warn "no deny.toml: checking advisories, bans and sources only (add one to enforce licenses)"
    cargo deny --locked check advisories bans sources
  fi
fi

if is_true "${RUN_AUDIT:-true}"; then
  ensure_tool cargo-audit cargo-audit || die "cargo-audit not installed (INSTALL_TOOLS=false)"
  log "cargo audit"
  cargo audit
fi
