#!/usr/bin/env bash
# osv-scanner (OSV.dev) dependency scan of lockfiles / manifests / a CycloneDX
# SBOM, gated on CVSS score. Installs a pinned, checksum-verified osv-scanner
# when it is not on PATH.
#
# Env in:
#   SCAN_TARGET          file (lockfile, pom.xml, bom.json, ...) or directory
#                        (scanned recursively), default .
#   FAIL_SEVERITIES      comma list (CRITICAL,HIGH,MEDIUM,LOW); the lowest one sets
#                        the CVSS gate: CRITICAL>=9.0 HIGH>=7.0 MEDIUM>=4.0 LOW>0.
#                        Default CRITICAL. Unscored advisories never fail the gate.
#   FAIL_ON_FINDINGS     true/false, default true
#   OSV_SCANNER_VERSION  default 2.7.1 (used only when installing)
#   OSV_ARGS             extra osv-scanner arguments (e.g. --config osv-scanner.toml)
#   CI_OUT_DIR           output dir, default ./.ci-out
# Files out ($CI_OUT_DIR):
#   osv.json
# Outputs: osv_json, osv_findings
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_cmd jq curl

out="$(out_dir)"
target="${SCAN_TARGET:-.}"
[[ -e "${target}" ]] || die "SCAN_TARGET ${target} not found"

install_osv() {
  local v os arch asset dir sums want got
  v="${OSV_SCANNER_VERSION:-2.7.1}"
  os="$(lower "$(uname -s)")"
  case "$(uname -m)" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) die "unsupported architecture $(uname -m)" ;;
  esac
  asset="osv-scanner_${os}_${arch}"
  dir="${TMPDIR:-/tmp}/koorikla-ci-bin"
  mkdir -p "${dir}"
  log "installing osv-scanner ${v} (${asset})"
  curl -fsSL -o "${dir}/osv-scanner" "https://github.com/google/osv-scanner/releases/download/v${v}/${asset}"
  sums="$(curl -fsSL "https://github.com/google/osv-scanner/releases/download/v${v}/osv-scanner_SHA256SUMS")"
  want="$(printf '%s\n' "${sums}" | awk -v a="${asset}" '$2 == a {print $1}')"
  [[ -n "${want}" ]] || die "no checksum for ${asset}"
  if command -v sha256sum >/dev/null 2>&1; then
    got="$(sha256sum "${dir}/osv-scanner" | awk '{print $1}')"
  else
    got="$(shasum -a 256 "${dir}/osv-scanner" | awk '{print $1}')"
  fi
  [[ "${got}" == "${want}" ]] || die "osv-scanner checksum mismatch (${got} != ${want})"
  chmod 0755 "${dir}/osv-scanner"
  PATH="${dir}:${PATH}"
  export PATH
}

command -v osv-scanner >/dev/null 2>&1 || install_osv

fail_sev="$(printf '%s' "${FAIL_SEVERITIES:-CRITICAL}" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')"
gate="9.0"
case ",${fail_sev}," in
  *,LOW,*) gate="0.1" ;;
  *,MEDIUM,*) gate="4.0" ;;
  *,HIGH,*) gate="7.0" ;;
esac

if [[ -d "${target}" ]]; then
  set -- -r "${target}"
else
  set -- -L "${target}"
fi
# shellcheck disable=SC2086
set -- "$@" ${OSV_ARGS:-}

log "osv-scanner scan source $*"
rc=0
osv-scanner scan source --format json --output-file "${out}/osv.json" "$@" || rc=$?
# 0 = clean, 1 = vulnerabilities found, 128 = no packages found, other = error.
case "${rc}" in
  0 | 1) ;;
  128)
    warn "osv-scanner found no packages in ${target}"
    printf '{"results":[]}\n' >"${out}/osv.json"
    ;;
  *) die "osv-scanner failed (exit ${rc})" ;;
esac
emit_output osv_json "${out}/osv.json"

total="$(jq '[.results[]?.packages[]?.groups[]?] | length' "${out}/osv.json")"
n="$(jq --argjson g "${gate}" '
      [.results[]?.packages[]?.groups[]?
       | (.max_severity // "" | tonumber? // 0) | select(. >= $g)] | length' "${out}/osv.json")"
emit_output osv_findings "${n}"
log "osv-scanner: ${total} advisories (deduplicated groups); ${n} with CVSS >= ${gate} (${fail_sev})"
step_summary "- osv-scanner \`${target}\`: ${total} advisories; ${n} at CVSS >= ${gate}"

if [[ "${n}" -gt 0 ]]; then
  jq -r --argjson g "${gate}" '
    .results[]?.packages[]? as $p
    | $p.groups[]? | select((.max_severity // "" | tonumber? // 0) >= $g)
    | "  \($p.package.name)@\($p.package.version): \(.ids | join(", ")) (CVSS \(.max_severity))"' \
    "${out}/osv.json" >&2
  if is_true "${FAIL_ON_FINDINGS:-true}"; then
    die "${n} dependency advisories at CVSS >= ${gate}"
  fi
  warn "${n} dependency advisories at CVSS >= ${gate} (not failing)"
fi
