# Android and macOS previews

The Android and macOS targets share the same Dart code and repository as Windows and Ubuntu. These are experimental packages, not equivalent to the validated desktop releases yet.

## Android

The APK is intended for ARM64 Android phones (Android 7.0/API 24 or newer). A separate x86_64 APK is built for emulator validation. Application ID: `app.musictime.player.preview`.

CI preview APKs use Android's debug signing identity even though the Flutter build is optimized. They are not Play Store releases. A later preview built on another runner may require uninstalling the previous preview first, which removes its app data. Network access is enabled; automatic Android cloud backup is disabled to avoid exporting the app's private catalog and settings.

The desktop-oriented layout, folder access under scoped storage, device EQ, authentication callbacks, background playback, media notifications and lock-screen controls need Android-specific acceptance. Do not infer full mobile support from successful compilation. Select individual files when folder selection is unsupported.

## macOS

Requires macOS 12 or later. Download the preview zip from the [unified 3.0.11 release](https://github.com/eugilvando/Music-Time-Player/releases/tag/v3.0.11) and extract the `.app`. The executable and all 16 bundled native libraries/framework binaries contain both x86_64 and arm64 slices (Intel and Apple Silicon). The app is not signed with an Apple Developer ID or notarized; macOS may block opening it until the user explicitly allows it. It is not an App Store package.

The sandbox permits network clients and user-selected files. Long-term folder access, secure credential storage, media controls, output devices and audio playback need validation on a real Mac. Keep the existing Windows/Ubuntu releases for production use until this platform is accepted.

## Reproducibility

Use Flutter 3.47.7 and the committed lockfile. Android requires JDK 17+, the Android SDK/NDK and its accepted licenses. macOS requires a Mac with Xcode and CocoaPods when a plugin needs it. The `Platform previews` workflow builds packages and uploads artifacts without requiring a second source checkout for development.

## Release organization

Keep development in this one repository: shared application code in `lib/`, platform runners in `windows/`, `linux/`, `android/` and `macos/`. Publish platform installers as assets of one version release (`v3.0.11` for these packages), not separate operating-system releases. Package names identify the platform; preview status is stated per package. Source tags and historical documentation remain even when old release downloads are removed.

The `Platform previews` workflow builds both new targets. The `Android preview startup` workflow accepts its run ID and installs the optimized x86_64 APK in an Android 15 emulator. These checks do not replace real-device testing. No personal library or connected account is used in CI.
