# syntax=docker/dockerfile:1
# Quarkus native executable (Mandrel) on the Quarkus distroless base, non-root.
# GraalVM/Mandrel cannot cross-compile: this builds on the target platform, i.e.
# one native runner per arch (koorikla/ci java.yaml native: true). Expect a few
# minutes and several GiB of RAM per arch.
ARG BUILDER_IMAGE=quay.io/quarkus/ubi9-quarkus-mandrel-builder-image:jdk-25.0.5@sha256:38f943afcae3218771546a99b41156dd3efa8315483eaf74f88f33d232bb3c8d

FROM ${BUILDER_IMAGE} AS build
WORKDIR /project
COPY --chown=quarkus:quarkus . .
RUN --mount=type=cache,target=/home/quarkus/.m2,uid=1001 --mount=type=cache,target=/home/quarkus/.gradle,uid=1001 \
    set -eu; \
    if [ -f mvnw ]; then \
      sh ./mvnw -B -ntp -DskipTests -Dnative package && cp target/*-runner /project/application; \
    elif [ -f gradlew ]; then \
      sh ./gradlew --no-daemon -x test build -Dquarkus.native.enabled=true -Dquarkus.package.jar.enabled=false && cp build/*-runner /project/application; \
    else echo "no mvnw or gradlew"; exit 1; fi

FROM quay.io/quarkus/quarkus-distroless-image:2.0@sha256:30c6ef88c81b1ea9a6aaedf413f8515b26b7a58fda4b888e6df4ba78118eb3da
COPY --from=build /project/application /application
ARG VERSION=dev
ENV VERSION=${VERSION}
USER nonroot
EXPOSE 8080
CMD ["/application", "-Dquarkus.http.host=0.0.0.0"]
