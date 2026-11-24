# Static audit and corrective changes — v1.5.11

## Findings in v1.5.10
1. `android/gradle/wrapper/gradle-wrapper.jar` was absent. `chmod +x gradlew` alone cannot fix a missing wrapper JAR.
2. App version declarations were inconsistent (`pubspec.yaml` 1.5.5+20 vs Android 1.5.0).
3. API helper did not clear an expired local JWT on HTTP 401; multipart report/post/profile/verification flows also needed handling.
4. Map page still used OSM standard raster tiles; header contrast could be poor on a dark inherited surface.

## Changes in v1.5.11
- Provision Gradle 8.14 directly with `gradle/actions/setup-gradle@v4`.
- Regenerate the Gradle wrapper during CI, verify the JAR exists, then make the script executable.
- Pin Java 17.
- Align Flutter and Android app version declarations to 1.5.11 (build 26).
- Clear expired local auth token on 401 across regular and multipart API flows.
- Use a light header surface and CARTO Voyager map tiles.

## Not claimed as verified
No Flutter SDK/Android SDK build was run in this container. GitHub Actions must verify `flutter analyze`, APK and AAB. Live authentication, database connectivity, map tile loading and Cloudflare R2 uploads require real Render/R2 credentials and device testing. The Render database host previously returned Prisma P1001; this archive cannot repair an unavailable or incorrect database URL.
