#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -m)" = x86_64
bundle=build/linux/x64/release/bundle
test -x "$bundle/music_time"
test -f "$bundle/lib/libapp.so"
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)-0ubuntu1~preview2"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
install -d "$stage/DEBIAN" "$stage/opt/music-time-preview" "$stage/usr/bin" \
  "$stage/usr/share/applications" "$stage/usr/share/icons/hicolor/256x256/apps" \
  "$stage/usr/share/doc/music-time-preview" dist/ubuntu
cp -a "$bundle/." "$stage/opt/music-time-preview/"
install -m 755 scripts/launch-ubuntu.sh "$stage/usr/bin/music-time-preview"
install -m 644 assets/branding/icon.png "$stage/usr/share/icons/hicolor/256x256/apps/music-time-preview.png"
install -m 644 docs/ubuntu-preview.md "$stage/usr/share/doc/music-time-preview/README.md"
if test -f LICENSE; then install -m 644 LICENSE "$stage/usr/share/doc/music-time-preview/copyright"; fi
if test -f THIRD_PARTY_NOTICES.md; then
  install -m 644 THIRD_PARTY_NOTICES.md "$stage/usr/share/doc/music-time-preview/THIRD_PARTY_NOTICES.md"
fi
if test -d LICENSES; then cp -a LICENSES "$stage/usr/share/doc/music-time-preview/"; fi
cat > "$stage/usr/share/applications/music-time-preview.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Music Time (Ubuntu Preview)
Comment=Personal music player — experimental Ubuntu build
Exec=music-time-preview
Icon=music-time-preview
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupWMClass=app.musictime.preview
DESKTOP
cat > "$stage/DEBIAN/control" <<CONTROL
Package: music-time-preview
Version: $version
Architecture: amd64
Maintainer: Gilvando Souza
Section: sound
Priority: optional
Depends: libc6 (>= 2.39), libstdc++6, libgtk-3-0t64, libsecret-1-0, libmpv2, libsqlite3-0, libx11-6, libxi6, libblkid1, liblzma5, libglu1-mesa, libasound2t64, gnome-keyring, xdg-utils
Description: Music Time experimental Ubuntu 24.04 desktop player
 Local and cloud music catalog, audio playback and playlists.
 Separate preview package; desktop integrations require VM testing.
CONTROL
find "$stage" -type d -exec chmod 755 {} +
dpkg-deb --root-owner-group --build "$stage" "dist/ubuntu/music-time-preview_${version}_amd64.deb"
cp docs/ubuntu-preview.md dist/ubuntu/README.md
(cd dist/ubuntu && sha256sum ./*.deb > SHA256SUMS.txt)
dpkg-deb --info "dist/ubuntu/music-time-preview_${version}_amd64.deb"
