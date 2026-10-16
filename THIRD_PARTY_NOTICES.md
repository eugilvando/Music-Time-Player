# Third-party notices

The [MIT License](LICENSE) applies to Music Time's own code. It does not relicense dependencies, bundled native libraries, music, provider trademarks or user-supplied artwork.

## Flutter and Dart dependencies

Flutter/Dart and the packages selected by `pubspec.lock` retain their original notices. Generated full notices are included in `LICENSES/FLUTTER-NOTICES.txt` and `LICENSES/DART-PACKAGES.txt`. The Flutter application bundle also contains its generated `NOTICES.Z` asset.

Major dependencies include Flutter (BSD-style), MediaKit (MIT), SQLite (public domain), the Dart HTTP/XML/FFI packages and the Windows integration plugins. Consult the included license texts for the exact package version and terms; this paragraph is not a replacement for those texts.

## Native playback library

The Windows bundle dynamically loads **libmpv-2.dll** selected by `media_kit_libs_windows_audio 1.0.9`. Its package recipe selects:

- Upstream binary release: [media-kit/libmpv-win32-audio-build, 2023-09-24](https://github.com/media-kit/libmpv-win32-audio-build/releases/tag/2023-09-24).
- Archive: `mpv-dev-x86_64-20230924-git-652a1dd.7z`.
- Upstream archive MD5 used by the package: `cd738e16e2a19626d7cfa48801524f8c`.
- The upstream binary contains FFmpeg configuration flags `--disable-gpl --disable-nonfree --enable-version3`. The upstream mpv recipe uses `gpl=false`; native components retain their applicable LGPL and other licenses.

Sources and build recipes: [mpv](https://github.com/mpv-player/mpv), [FFmpeg](https://github.com/FFmpeg/FFmpeg), [Windows audio build recipes](https://github.com/media-kit/libmpv-win32-audio-build). The release's native provenance manifest records the shipped DLL hash and the selected upstream archive. LGPL/GPL license texts are supplied under `LICENSES/`; the inclusion of GPL text also provides the base terms referred to by LGPLv3, and does not label Music Time's own source as GPL.

The library is a separate replaceable DLL; the application does not add a restriction against modifications/reverse engineering permitted by the applicable LGPL terms. If redistributing a modified native library, preserve its notices and provide the corresponding source/build material required by its license. Music Time's source archive alone is not the source of every third-party native dependency.

## Windows runtime and fonts

Windows builds include Microsoft Visual C++ runtime files redistributed under Microsoft's applicable terms, not MIT. Windows itself and system fonts are not bundled as source assets. Demo screenshots render Segoe UI from the Windows system; no Segoe font files are included in the repository.

The generated artwork and fictional catalog used in screenshots were created for this project and are not an included commercial music library. Provider and server names identify their respective third-party products; this project is not an official Google, Microsoft, Last.fm, Jellyfin or Emby client endorsed by those providers.
