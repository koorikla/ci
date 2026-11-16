#!/usr/bin/env bash
# JVM checks (Quarkus, Spring Boot, plain Java/Kotlin) with Maven or Gradle
# (wrapper preferred): compile + tests (`verify` / `build`), JaCoCo coverage
# report and a CycloneDX SBOM of the resolved runtime dependencies.
#
# Maven needs no pom changes: JaCoCo and CycloneDX run as fully qualified
# plugin goals. Gradle: JaCoCo/CycloneDX run when the build applies the
# `jacoco` / `org.cyclonedx.bom` plugins (tasks jacocoTestReport, cyclonedxBom).
#
# Env in:
#   WORKDIR            project directory, default .
#   BUILD_TOOL         auto | maven | gradle, default auto (scripts/java/detect.sh)
#   RUN_TESTS          default true (false = -DskipTests / -x test)
#   COVERAGE           default true (JaCoCo)
#   SBOM               default true (CycloneDX JSON)
#   BUILD_ARGS         extra arguments for mvn / gradle (e.g. -Pci)
#   JACOCO_VERSION     default 0.8.16 (Maven)
#   CYCLONEDX_MAVEN_VERSION default 2.9.3 (Maven)
#   CI_OUT_DIR         output dir, default ./.ci-out
# Files out:
#   $CI_OUT_DIR/bom.cdx.json (CycloneDX SBOM), JaCoCo reports under target/ or build/
# Outputs: build_tool, framework, sbom (absolute path, '' when none), coverage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/lib.sh
source "${SCRIPT_DIR}/../common/lib.sh"

require_cmd java
out="$(out_dir)"
case "${out}" in /*) ;; *) out="$(pwd)/${out}" ;; esac

meta="$(mktemp -d "${TMPDIR:-/tmp}/java-detect.XXXXXX")"
CI_OUT_DIR="${meta}" GITHUB_OUTPUT="" bash "${SCRIPT_DIR}/detect.sh"
tool="$(cat "${meta}/build_tool")"
cmd="$(cat "${meta}/build_cmd")"
framework="$(cat "${meta}/framework")"
rm -rf "${meta}"
emit_output build_tool "${tool}"
emit_output framework "${framework}"

cd "${WORKDIR:-.}"
case "${cmd}" in
  ./*) [[ -x "${cmd}" ]] || chmod +x "${cmd}" ;;
  *) require_cmd "${cmd}" ;;
esac
java -version 2>&1 | head -1 >&2

# mvnw verifies the pinned .zip distribution only when `unzip` exists (else it
# downloads the .tar.gz and the checksum fails). JDK images ship no unzip:
# provide a minimal one backed by `jar`.
if [[ "${cmd}" == "./mvnw" ]] && ! command -v unzip >/dev/null 2>&1; then
  require_cmd jar
  shim="$(mktemp -d "${TMPDIR:-/tmp}/unzip-shim.XXXXXX")"
  cat >"${shim}/unzip" <<'SHIM'
#!/bin/sh
# Minimal `unzip [-q] FILE -d DIR` for mvnw, backed by the JDK's jar tool.
set -eu
file="" dir="."
while [ $# -gt 0 ]; do
  case "$1" in
    -q) ;;
    -d) dir="$2"; shift ;;
    *) file="$1" ;;
  esac
  shift
done
case "$file" in /*) ;; *) file="$(pwd)/$file" ;; esac
mkdir -p "$dir" && cd "$dir" && jar xf "$file"
for f in */bin/*; do [ -f "$f" ] && chmod +x "$f"; done
SHIM
  chmod +x "${shim}/unzip"
  PATH="${shim}:${PATH}"
  export PATH
  log "no unzip on PATH: using a jar-backed shim for mvnw"
fi

case "${tool}" in
  maven)
    jv="${JACOCO_VERSION:-0.8.16}"
    cv="${CYCLONEDX_MAVEN_VERSION:-2.9.3}"
    set -- -B -ntp -e
    if is_true "${COVERAGE:-true}" && is_true "${RUN_TESTS:-true}"; then
      set -- "$@" "org.jacoco:jacoco-maven-plugin:${jv}:prepare-agent"
    fi
    set -- "$@" verify
    if is_true "${COVERAGE:-true}" && is_true "${RUN_TESTS:-true}"; then
      set -- "$@" "org.jacoco:jacoco-maven-plugin:${jv}:report"
    fi
    if is_true "${SBOM:-true}"; then
      set -- "$@" "org.cyclonedx:cyclonedx-maven-plugin:${cv}:makeAggregateBom" \
        -DoutputFormat=json -DoutputName=bom -DprojectType=application -Dcyclonedx.skipNotDeployed=false
    fi
    if ! is_true "${RUN_TESTS:-true}"; then
      set -- "$@" -DskipTests
    fi
    ;;
  gradle)
    log "${cmd} tasks --all (detecting jacoco / cyclonedx tasks)"
    tasks="$("${cmd}" --no-daemon -q tasks --all 2>/dev/null || true)"
    has_task() {
      printf '%s\n' "${tasks}" | grep -Eq "^([^ ]*:)?$1( |$)"
    }
    set -- --no-daemon --stacktrace build
    if ! is_true "${RUN_TESTS:-true}"; then
      set -- "$@" -x test
    fi
    if is_true "${COVERAGE:-true}" && is_true "${RUN_TESTS:-true}"; then
      if has_task jacocoTestReport; then
        set -- "$@" jacocoTestReport
      else
        warn "no jacocoTestReport task: apply the \`jacoco\` plugin for coverage"
      fi
    fi
    if is_true "${SBOM:-true}"; then
      if has_task cyclonedxBom; then
        set -- "$@" cyclonedxBom
      else
        warn "no cyclonedxBom task: apply plugin id(\"org.cyclonedx.bom\") for an SBOM (falling back to lockfile scans)"
      fi
    fi
    ;;
esac

# shellcheck disable=SC2086
log "${cmd} $* ${BUILD_ARGS:-}"
# shellcheck disable=SC2086
"${cmd}" "$@" ${BUILD_ARGS:-}

# Coverage: sum the report-level LINE counters of every JaCoCo XML report.
if is_true "${COVERAGE:-true}" && is_true "${RUN_TESTS:-true}"; then
  reports="$(find . \( -path '*/site/jacoco/jacoco.xml' -o -name 'jacocoTestReport.xml' \) -not -path '*/node_modules/*' 2>/dev/null || true)"
  if [[ -n "${reports}" ]]; then
    pct="$(printf '%s\n' "${reports}" | while IFS= read -r f; do
      grep -o '<counter type="LINE" missed="[0-9]*" covered="[0-9]*"/>' "${f}" | tail -1
    done | awk -F'"' '{ m += $4; c += $6 } END { if (m + c > 0) printf "%.1f%%", 100 * c / (m + c) }')"
    if [[ -n "${pct}" ]]; then
      log "JaCoCo line coverage: ${pct}"
      emit_output coverage "${pct}"
      step_summary "- JaCoCo line coverage (\`${WORKDIR:-.}\`): ${pct}"
    fi
  else
    warn "no JaCoCo XML report found"
  fi
fi

sbom=""
if is_true "${SBOM:-true}"; then
  if [[ "${tool}" == "maven" ]]; then
    [[ -f target/bom.json ]] && sbom="target/bom.json"
  else
    sbom="$(find . -path '*/build/reports/*' \( -name 'bom.json' -o -name '*.cdx.json' \) 2>/dev/null |
      awk '{ print length($0) " " $0 }' | sort -n | head -1 | cut -d' ' -f2-)"
  fi
  if [[ -n "${sbom}" ]]; then
    cp "${sbom}" "${out}/bom.cdx.json"
    sbom="${out}/bom.cdx.json"
    n="$(grep -o '"purl"' "${sbom}" | wc -l | tr -d ' ')"
    log "CycloneDX SBOM: ${sbom} (${n} components)"
    step_summary "- CycloneDX SBOM: ${n} components"
  else
    warn "no CycloneDX SBOM produced"
  fi
fi
emit_output sbom "${sbom}"
