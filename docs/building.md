# Build Music Time on Windows

[README](../README.md) · [Provider configuration](provider-setup.md)

## Requirements

- Windows x64.
- Flutter **3.47.7** / Dart **3.13.5**, the validated baseline. Respect `pubspec.yaml`'s Dart requirement and `pubspec.lock`.
- Visual Studio 2022 with Desktop development with C++, Windows SDK and the components required by `flutter doctor`.
- Inno Setup 6 for the installer.
- Git and network access to download Flutter/Dart/native build dependencies.

Flutter is required for development, not for users of the installer. Keep the checkout and SDK in short writable paths; OneDrive/file-locking tools can interfere with native builds and cleanup.

## Build, analyze and test

From the repository root:

```powershell
flutter doctor
flutter pub get
dart analyze --fatal-infos
flutter build windows --release
$env:MUSIC_TIME_LIBMPV = Join-Path $PWD 'build/windows/x64/runner/Release/libmpv-2.dll'
flutter test --no-pub --concurrency=1
```

The default test suite contains 297 baseline cases. `MUSIC_TIME_LIBMPV` selects the built playback library for native tests; build it first. Test fixtures use temporary or in-memory data. Material-icon test fonts are resolved from this checkout's active Flutter SDK rather than a developer-specific absolute path.

Optional native checks use temporary validation profiles:

```powershell
.\scripts\test-windows-integration.ps1 -Executable "$PWD\build\windows\x64\runner\Release\music_time.exe"
.\scripts\test-data-restart.ps1 -Executable "$PWD\build\windows\x64\runner\Release\music_time.exe"
```

Do not use an active personal profile for reset/restore tests. Do not interpret account mocks as live Google/Microsoft/server validation.

## Create an installer

```powershell
.\scripts\build-installer.ps1 -FlutterSdk 'C:\path\to\flutter'
```

The script checks formatting and analysis, builds Windows, runs tests/native checks, copies the C++ runtime, prepares notices and calls Inno Setup. Output: `dist/MusicTime-Setup-1.2.1.exe`.

Application binaries live in `build/windows/x64/runner/Release/`. Distribute the complete bundle or the installer, not only `music_time.exe`. Keep third-party licenses/notices with the binaries. See [third-party notices](../THIRD_PARTY_NOTICES.md) and `LICENSES/`.

You do not need to embed provider IDs when building. The installed UI accepts each user's own Microsoft/Google registration. `config.example.json` documents the optional Microsoft build define; do not commit a populated local configuration or private credentials.

## Reproduce the screenshots

```powershell
$env:MUSIC_TIME_LIBMPV = Join-Path $PWD 'build/windows/x64/runner/Release/libmpv-2.dll'
flutter test --no-pub tool/capture_screenshots_test.dart
```

This renders the real application widgets with a fictional catalog, generated artwork and in-memory application data. It writes `docs/images/*.png` and does not open a personal database or connect a provider. Windows Segoe UI is used only at rendering time. The artwork/lyrics are demo fixtures; the screenshots do not prove server connectivity.

## Structure

`lib/` contains the application, `test/` the tests, `windows/` the runner, `assets/` production artwork, `installer/` the Inno definition, `scripts/` build/native tooling, `tool/` the screenshot harness and `docs/` the public guides. `release/` stores checksum/provenance/validation metadata; binaries are GitHub release assets instead of Git history.
