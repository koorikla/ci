# syntax=docker/dockerfile:1
# Quarkus (JVM mode) on distroless Java 25, non-root. The jar is
# platform-independent, so it is built once on the build host ($BUILDPLATFORM,
# no emulation) and copied into each target platform's runtime image.
# Maven (mvnw) or Gradle (gradlew) is picked from the wrapper present.
ARG JDK_IMAGE=docker.io/library/eclipse-temurin:25.0.5_8-jdk-noble@sha256:80f67fb3d6f76e2d817d98a4cc2a9cf05f054d4e6adc5e2144bde671d722e63f

FROM --platform=$BUILDPLATFORM ${JDK_IMAGE} AS build
# mvnw picks the .zip distribution (whose checksum is pinned) only when unzip exists.
RUN apt-get update && apt-get install -y --no-install-recommends unzip && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .
RUN --mount=type=cache,target=/root/.m2 --mount=type=cache,target=/root/.gradle \
    set -eu; \
    if [ -f mvnw ]; then \
      sh ./mvnw -B -ntp -DskipTests package && cp -r target/quarkus-app /out; \
    elif [ -f gradlew ]; then \
      sh ./gradlew --no-daemon -x test build && cp -r build/quarkus-app /out; \
    else echo "no mvnw or gradlew"; exit 1; fi

FROM gcr.io/distroless/java25-debian13:nonroot@sha256:1c4ced761d17961c900cba60c33c8c3c46edbdadaa9d5ef9806eb5a6824fd406
WORKDIR /deployments
COPY --from=build /out/lib/ ./lib/
COPY --from=build /out/*.jar ./
COPY --from=build /out/app/ ./app/
COPY --from=build /out/quarkus/ ./quarkus/
ARG VERSION=dev
ENV VERSION=${VERSION} \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -Djava.util.logging.manager=org.jboss.logmanager.LogManager"
USER nonroot:nonroot
EXPOSE 8080
# ENTRYPOINT is ["/usr/bin/java", "-jar"]
CMD ["/deployments/quarkus-run.jar"]
