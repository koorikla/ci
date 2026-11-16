#!/usr/bin/env bash
# Detect the build tool and framework of a JVM project.
#
# Build tool: Maven (pom.xml) or Gradle (build.gradle[.kts] / settings.gradle[.kts]);
# the wrapper (mvnw / gradlew) is preferred over a system install.
# Framework: quarkus (io.quarkus), spring-boot (org.springframework.boot), else plain.
#
# Env in:
#   WORKDIR     project directory, default .
#   BUILD_TOOL  auto | maven | gradle, default auto
# Outputs:
#   build_tool  maven | gradle
#   build_cmd   ./mvnw | mvn | ./gradlew | gradle
#   framework   quarkus | spring-boot | plain
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/lib.sh
source "${SCRIPT_DIR}/../common/lib.sh"

wd="${WORKDIR:-.}"
tool="${BUILD_TOOL:-auto}"
if [[ "${tool}" == "auto" ]]; then
  if [[ -f "${wd}/pom.xml" ]]; then
    tool=maven
  elif has_file "${wd}/build.gradle" "${wd}/build.gradle.kts" "${wd}/settings.gradle" "${wd}/settings.gradle.kts"; then
    tool=gradle
  else
    die "no pom.xml or build.gradle[.kts] in ${wd}"
  fi
fi

case "${tool}" in
  maven)
    if [[ -f "${wd}/mvnw" ]]; then cmd=./mvnw; else cmd=mvn; fi
    files="${wd}/pom.xml"
    ;;
  gradle)
    if [[ -f "${wd}/gradlew" ]]; then cmd=./gradlew; else cmd=gradle; fi
    files=""
    for f in build.gradle build.gradle.kts settings.gradle settings.gradle.kts gradle/libs.versions.toml; do
      [[ -f "${wd}/${f}" ]] && files="${files} ${wd}/${f}"
    done
    ;;
  *) die "unsupported BUILD_TOOL ${tool}" ;;
esac
if [[ "${cmd}" == "mvn" || "${cmd}" == "gradle" ]]; then
  warn "no ${tool} wrapper in ${wd}; using the system ${cmd} (pin it with the wrapper)"
fi

framework=plain
# shellcheck disable=SC2086
content="$(cat ${files} 2>/dev/null || true)"
case "${content}" in
  *io.quarkus*) framework=quarkus ;;
  *org.springframework.boot*) framework=spring-boot ;;
esac

emit_output build_tool "${tool}"
emit_output build_cmd "${cmd}"
emit_output framework "${framework}"
log "build tool=${tool} (${cmd}) framework=${framework}"
