# Music Time — Ubuntu 24.04 x64 Preview 2.5.4

Experimental Ubuntu package based on Music Time **2.5.4+56**. The same preview application ID (`app.musictime.preview`) and Debian package name (`music-time-preview`) are preserved for in-place upgrades from 2.4.1. Windows installation and the stable Windows release remain independent.

Includes the Windows 2.5.4 catalog/UI features: reversible shuffle and visible queue order, Home/Insights session caching, artist radio/mix improvements, source reconciliation for missing/renamed tracks, selectable source paths, hidden-item filters, and sidebar drag ordering. Linux-specific desktop limitations remain below.

## Install or upgrade

Close the previous instance first. Download the `.deb` and checksum into the same folder:

```sh
sha256sum -c SHA256SUMS.txt
sudo apt update
sudo apt install ./music-time-preview_2.5.4-0ubuntu1*preview1_amd64.deb
music-time-preview
```

The package is built for **Ubuntu Desktop 24.04 amd64**. Debian internal version: `2.5.4-0ubuntu1~preview1`. GitHub may replace `~` with `.` in the download filename; the wildcard above accepts both. apt installs required dependencies. Do not run the application with sudo. Back up your existing Linux profile before upgrading; do not overwrite your only Windows database copy for VM testing. SQLite18 and backup17/container2 remain unchanged from 2.4.1.

## Graphics in VMware and other VMs

Impeller remains disabled in the Linux runner. The default **compatibility** mode uses Skia, Mesa CPU OpenGL and X11 to avoid the virtual GPU path associated with the previously reported artifacts. It can use more CPU; retest on your own VM.

Close the application before changing renderer:

```sh
# Alternative CPU rendering path
MUSIC_TIME_RENDERER=software music-time-preview

# Explicit hardware rendering for comparison
MUSIC_TIME_RENDERER=hardware music-time-preview
```

Keep VMware 3D enabled or compare with it disabled after powering off the VM. The default software-GL path does not require changing VM settings. Diagnostics: `music-time-preview > ~/music-time-preview.log 2>&1`; review paths before sharing logs.

## Scope and credentials

- Local files, library, playlists, favorites, metadata, downloads/cache and the Flutter UI are included. Real audio formats, devices, accounts and VM behavior require your own testing; CI cannot prove personal account access or speaker output.
- Windows tray/SMTC, system accent and startup integrations are not activated on Linux. Closing the window exits this preview. Some Windows-specific settings may still appear.
- Mount SMB shares in Ubuntu and add them as local folders. The Windows UNC integration is not ported.
- OneDrive and Google Drive require your own application registration/Client ID and authorization in Ubuntu. Windows secure-storage sessions are not automatically portable. Unlock GNOME Keyring in your graphical login session. See [provider setup](https://github.com/eugilvando/Music-Time-Player/blob/main/docs/provider-setup.md).
- After upgrading, synchronize the source to retire missing/renamed old files. Failed/cancelled scans preserve the prior catalog. Manual hide/show is under Library filters and does not delete original files or existing playlist occurrences.

## Verify in the VM

Add a small local folder, check artwork/tags/duration/disc order, play MP3/FLAC, pause/seek, use EQ, save playlists, restart, and verify paused session restoration. Then test a cloud folder, offline/cache behavior, hidden items and the sidebar organizer. Test graphics in full and half-screen sizes.

```sh
sudo apt remove music-time-preview
```

Removing the package preserves user data and original music. macOS remains future work.

## Português brasileiro

Prévia Ubuntu atualizada com a base **2.5.4+56**, preservando o perfil e o identificador da 2.4.1. Feche a versão anterior e instale pelo apt com o comando acima. O modo padrão mantém a compatibilidade gráfica para VMware; se necessário, use a alternativa `software`. Testes/build/abertura gráfica em CI são distintos do aceite real de áudio, contas e da sua VM. O relatório de validação e o checksum acompanham a release. Faça uma cópia do perfil Linux antes de atualizar. Windows permanece independente.

## Published build — 30 October 2026

[Download Ubuntu 2.5.4 Preview 1](https://github.com/eugilvando/Music-Time-Player/releases/tag/v2.5.4-ubuntu-preview.1). [Successful Ubuntu CI](https://github.com/eugilvando/Music-Time-Player/actions/runs/41122462183), source commit `c6587f03409867dffa2335c4c797db82526712b2`. Analysis, 85 targeted tests, release build, apt installation and graphical launch in compatibility/software modes passed. Six Home/Settings/resized screenshots were inspected without observed geometry corruption. The CI host has no ALSA output; the fixture playback error in captures does not validate real speaker output or formats. Retest audio, accounts and your VMware VM separately.

Debian package: 12259326 bytes. SHA256: `870fa14c8c8800fc2dff04e7b9569078123f35a792357482e7a06e07fe8e769f`. Four release attachments: .deb, SHA256SUMS.txt, README-ubuntu-preview.md and validation-ubuntu.json. Remote digests were checked. The Windows stable/latest release remains v2.5.4.

## Build from source

Use the public `codex/ubuntu-preview-2.5.4` branch on Ubuntu 24.04 with Flutter 3.47.7/Dart 3.13, GTK3/X11/Xi, libsecret, mpv and SQLite development dependencies. Run `flutter pub get`, `flutter analyze`, `flutter build linux --release` and `bash scripts/package-ubuntu.sh`. The workflow lists the complete build dependencies and targeted regressions.

For a future update based on a new Windows main, retain **linux/**, **scripts/launch-ubuntu.sh**, **scripts/package-ubuntu.sh**, **scripts/smoke-ubuntu.sh** and **.github/workflows/ubuntu-preview.yml** from the validated preview branch; update branch/artifact versions and documentation. The workflow checks these shell inputs before compiling. Preserve the preview application ID and renderer compatibility choices.
