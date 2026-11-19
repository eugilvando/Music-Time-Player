# Android and macOS previews

The Android and macOS targets share the same Dart code and repository as Windows and Ubuntu. These are experimental packages, not equivalent to the validated desktop releases yet.

## Android

The APK is intended for ARM64 Android phones (Android 7.0/API 24 or newer). A separate x86_64 APK is built for emulator validation. Application ID: `app.musictime.player.preview`.

CI preview APKs use Android's debug signing identity even though the Flutter build is optimized. They are not Play Store releases. A later preview built on another runner may require uninstalling the previous preview first, which removes its app data. Network access is enabled; automatic Android cloud backup is disabled to avoid exporting the app's private catalog and settings.

The desktop-oriented layout, folder access under scoped storage, device EQ, authentication callbacks, background playback, media notifications and lock-screen controls need Android-specific acceptance. Do not infer full mobile support from successful compilation. Select individual files when folder selection is unsupported.

## macOS

Download the preview zip and extract the `.app`. Build metadata lists the actual executable architectures. The app is not signed with an Apple Developer ID or notarized; macOS may block opening it until the user explicitly allows it. It is not an App Store package.

The sandbox permits network clients and user-selected files. Long-term folder access, secure credential storage, media controls, output devices and audio playback need validation on a real Mac. Keep the existing Windows/Ubuntu releases for production use until this platform is accepted.

## Reproducibility

Use Flutter 3.47.7 and the committed lockfile. Android requires JDK 17+, the Android SDK/NDK and its accepted licenses. macOS requires a Mac with Xcode and CocoaPods when a plugin needs it. The `Platform previews` workflow builds packages and uploads artifacts without requiring a second source checkout for development.
