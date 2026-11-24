# v1.5.10 — Gradle wrapper permission fix

The Java 17 setup is now confirmed by CI logs. The next failure was `./gradlew: Permission denied` (exit 126), meaning the Gradle wrapper script was checked out without its executable bit.

Changes:
- Run `chmod +x android/gradlew` in the workflow before Gradle/Flutter builds.
- Invoke the wrapper with `bash ./gradlew --version` for the diagnostic check.
- Linux desktop GTK warnings from `flutter doctor` are unrelated to Android APK/AAB builds.

The next GitHub Actions run is needed to validate the fix. This does not validate live backend/database/media upload functionality.
