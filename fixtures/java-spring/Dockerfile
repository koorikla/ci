# syntax=docker/dockerfile:1
# Spring Boot on distroless Java 25, non-root, no buildpacks: the executable jar
# is built once on the build host ($BUILDPLATFORM, it is platform-independent)
# and exploded into its layers (dependencies, loader, snapshot deps, application)
# so a code change only rebuilds the last, small layer.
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
      sh ./mvnw -B -ntp -DskipTests package; dir=target; \
    elif [ -f gradlew ]; then \
      sh ./gradlew --no-daemon -x test bootJar; dir=build/libs; \
    else echo "no mvnw or gradlew"; exit 1; fi; \
    jar="$(find "$dir" -maxdepth 1 -name '*.jar' ! -name '*-plain.jar' ! -name '*-sources.jar' ! -name '*-javadoc.jar' | head -1)"; \
    [ -n "$jar" ] || { echo "no executable jar in $dir"; exit 1; }; \
    java -Djarmode=tools -jar "$jar" extract --layers --launcher --destination /out; \
    mkdir -p /out/dependencies /out/spring-boot-loader /out/snapshot-dependencies /out/application

FROM gcr.io/distroless/java25-debian13:nonroot@sha256:1c4ced761d17961c900cba60c33c8c3c46edbdadaa9d5ef9806eb5a6824fd406
WORKDIR /app
COPY --from=build /out/dependencies/ ./
COPY --from=build /out/spring-boot-loader/ ./
COPY --from=build /out/snapshot-dependencies/ ./
COPY --from=build /out/application/ ./
ARG VERSION=dev
ENV VERSION=${VERSION} JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/usr/bin/java", "org.springframework.boot.loader.launch.JarLauncher"]
