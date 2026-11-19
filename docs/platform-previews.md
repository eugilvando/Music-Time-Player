# macOS desktop preview

The macOS target shares the same Dart application and repository as Windows and Ubuntu. This experimental package is not equivalent to validated desktop releases yet.

## macOS

Requires macOS 12 or later. Download the preview zip from the [unified 3.0.11 release](https://github.com/eugilvando/Music-Time-Player/releases/tag/v3.0.11) and extract the `.app`. The executable and all 16 bundled native libraries/framework binaries contain both x86_64 and arm64 slices (Intel and Apple Silicon). The app is not signed with an Apple Developer ID or notarized; macOS may block opening it until the user explicitly allows it. It is not an App Store package.

The sandbox permits network clients and user-selected files. Long-term folder access, secure credential storage, media controls, output devices and audio playback need validation on a real Mac. Keep the existing Windows/Ubuntu releases for production use until this platform is accepted.

## Reproducibility

Use Flutter 3.47.7 and the committed lockfile. macOS requires a Mac with Xcode and CocoaPods when a plugin needs it. The `Platform previews` workflow builds packages and uploads artifacts without requiring a second source checkout for development.

## Release organization

Keep development in this one repository: shared application code in `lib/`, platform runners in `windows/`, `linux/` and `macos/`. Publish platform installers as assets of one version release (`v3.0.11` for these packages), not separate operating-system releases. Package names identify the platform; preview status is stated per package. Source tags and historical documentation remain even when old release downloads are removed.

The `macOS preview` workflow builds the macOS package and uploads its artifacts. This does not replace real-device testing. No personal library or connected account is used in CI.
