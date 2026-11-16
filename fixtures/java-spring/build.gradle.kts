// koorikla/ci selftest fixture: Spring Boot service built with Gradle (java.yaml).
plugins {
    java
    jacoco
    id("org.springframework.boot") version "4.1.2"
    id("io.spring.dependency-management") version "1.1.7"
    id("org.cyclonedx.bom") version "3.6.1"
}

group = "dev.koorikla.ci"
version = "0.1.0"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(25)
    }
}

repositories {
    mavenCentral()
}

jacoco {
    toolVersion = "0.8.16"
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-webmvc")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
    finalizedBy(tasks.jacocoTestReport)
}

tasks.jacocoTestReport {
    dependsOn(tasks.test)
    reports {
        xml.required = true
    }
}

// Only the executable (boot) jar; the Dockerfile extracts its layers.
tasks.jar {
    enabled = false
}
