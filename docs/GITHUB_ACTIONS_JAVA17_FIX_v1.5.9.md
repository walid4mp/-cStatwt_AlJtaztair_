# GitHub Actions Java/Gradle repair — v1.5.9

## Root cause
The previous workflow did not install or select a JDK. GitHub's Ubuntu runner supplied Java 25. Gradle 8.14 cannot run on Java 25, producing `Unsupported class file major version 69`.

## Change
- Install Eclipse Temurin JDK 17 explicitly using `actions/setup-java@v4`.
- Verify Java 17 before invoking Flutter/Gradle.
- Verify the Gradle wrapper runtime before building.
- Keep Gradle wrapper 8.14 and Android Gradle Plugin 8.11.1; both are suitable for the project's JDK 17 configuration.
- Keep Java/Kotlin bytecode targets at 17.

## Validation limits
This source archive has not been built on GitHub Actions in this environment. The next Actions run is the required real CI validation. A successful APK build does not by itself validate API connectivity, authentication, database access, or R2 uploads.
