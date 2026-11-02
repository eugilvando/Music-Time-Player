# Third-party notices

The [MIT License](LICENSE) applies to Music Time's own code. It does not relicense dependencies, bundled native libraries, music, provider trademarks or user-supplied artwork.

## Flutter and Dart dependencies

Flutter/Dart and the packages selected by `pubspec.lock` retain their original notices. Generated full notices are included in `LICENSES/FLUTTER-NOTICES.txt` and `LICENSES/DART-PACKAGES.txt`. The Flutter application bundle also contains its generated `NOTICES.Z` asset.

Major dependencies include Flutter (BSD-style), MediaKit (MIT), SQLite (public domain), the Dart HTTP/XML/FFI packages and the Windows integration plugins. Consult the included license texts for the exact package version and terms; this paragraph is not a replacement for those texts.

## Native playback library

The Windows bundle dynamically loads **libmpv-2.dll** pinned by `windows/audio_runtime.cmake`. Music Time 2.7.0 replaces the reduced MediaKit audio binary with an LGPL build containing the parametric audio filters:

- Upstream binary release: [zhongfly/mpv-winbuild, 2026-11-02-a687796d9d](https://github.com/zhongfly/mpv-winbuild/releases/tag/2026-11-02-a687796d9d).
- Archive: `mpv-dev-lgpl-x86_64-20261102-git-a687796d9d.7z`; an unchanged copy accompanies Music Time 2.7.0 because upstream daily binaries have limited retention.
- Archive SHA256: `8b61f89716f31a6a1a3c85dc9a16bd7c57c77062b843af8cc8b78f6b5912d2e9`.
- DLL SHA256: `0c05c3ae5f54563dcd69bed60c69d4baa0a5c19f95a044c5c4c0a253197be41f`.
- Upstream identifies this variant as LGPLv2.1+ libmpv linked to LGPLv3 FFmpeg, with incompatible dependencies disabled by its LGPL build recipe.

Sources and recipes: [mpv at a687796d9d](https://github.com/mpv-player/mpv/tree/a687796d9d), [Windows build at 25b58a7](https://github.com/zhongfly/mpv-winbuild/tree/25b58a7), [LGPL build patch](https://github.com/zhongfly/mpv-winbuild/blob/25b58a7/compile-lgpl-libmpv.patch), [upstream build run and dependency revisions](https://github.com/zhongfly/mpv-winbuild/actions/runs/41441239761), and [FFmpeg](https://github.com/FFmpeg/FFmpeg). The native provenance manifest records the archive and shipped DLL hashes. LGPL/GPL license texts are supplied under `LICENSES/`; GPL text also supplies the base terms referenced by LGPLv3 and does not label Music Time's own source as GPL.

Ubuntu links the distribution's separately installed libmpv and dependencies. AutoEQ support reads user-provided text profiles; Music Time does not bundle the AutoEq project's measurement database or code.

The library is a separate replaceable DLL; the application does not add a restriction against modifications/reverse engineering permitted by the applicable LGPL terms. If redistributing a modified native library, preserve its notices and provide the corresponding source/build material required by its license. Music Time's source archive alone is not the source of every third-party native dependency.

## Windows runtime and fonts

Windows builds include Microsoft Visual C++ runtime files redistributed under Microsoft's applicable terms, not MIT. Windows itself and system fonts are not bundled as source assets. The interface now bundles Inter and Bricolage Grotesque under their SIL Open Font Licenses, and Material Symbols Rounded under its Apache license. License texts are included in assets/fonts and LICENSES. No Segoe font files are included.

The generated artwork and fictional catalog used in screenshots were created for this project and are not an included commercial music library. Provider and server names identify their respective third-party products; this project is not an official Google, Microsoft, Last.fm, Jellyfin or Emby client endorsed by those providers.
