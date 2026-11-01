# Music Time — Ubuntu 24.04 x64 Preview 2.5.5

Experimental Ubuntu package based on **2.5.5+57**, retaining the existing `music-time-preview` package and `app.musictime.preview` profile identity. Windows 2.5.5 is independent.

## Install or upgrade

Close the previous instance and back up your Linux profile. Download the Debian package and SHA256SUMS.txt into the same folder:

```sh
sha256sum -c SHA256SUMS.txt
sudo apt update
sudo apt install ./music-time-preview_2.5.5-0ubuntu1*preview1_amd64.deb
music-time-preview
```

Internal Debian version: `2.5.5-0ubuntu1~preview1`. GitHub changes `~` to `.` in download filenames; the wildcard accepts both. Do not run the app with sudo. Existing library/profile is preserved during package upgrades; Windows credentials are not automatically transferable.

## Changes

- New track favorites are exported to the authorized Last.fm account, with persistent retries. Configure under Settings → Integrations → Last.fm. Unfavoriting locally does not unlove remotely. Requires API credentials and an authorized session; old favorites are not bulk-exported.
- Close/minimize-to-tray is now enabled on Linux. Restore and playback/exit actions are available in the tray menu. Ubuntu needs the AppIndicator extension active. Without an active StatusNotifier host, the app keeps the window reachable rather than hiding it.
- The window's themed icon and installed desktop filename match its existing application ID. Unpin/re-pin an older dock shortcut if necessary after upgrade.
- Windows SMTC/accent/startup features remain Windows-only. Mount SMB shares in Ubuntu and add local folders.

## Graphics in VMware

Impeller stays disabled. Default compatibility mode uses Mesa CPU OpenGL and X11. Close the app before trying `MUSIC_TIME_RENDERER=software music-time-preview` or the opt-in hardware comparison `MUSIC_TIME_RENDERER=hardware music-time-preview`. Retest in your own VM; CPU rendering can use more CPU.

## Validation and real-machine acceptance

The attached validation manifest records the exact build commit, CI run, tests, package checksum and controlled graphical checks. CI does not prove speaker output, real cloud/Last.fm account access, GNOME tray behavior or VMware compatibility in your own environment.

On your VM or separate partition: verify dock/Alt+Tab icon, close/minimize/restore through the tray, playback continuity and Exit. Disable tray settings and verify normal behavior. Launch with AppIndicator disabled and confirm the window remains accessible; re-enable it and restart. Test a new Last.fm favorite online and offline, then reconnect and allow retries. Verify local/cloud playback and paused session restoration.

## Português brasileiro

Prévia **2.5.5+57** com favoritos enviados ao Last.fm e correções do ícone/bandeja Ubuntu. Feche o app, faça backup do perfil Linux e atualize pelo apt com o comando acima. A extensão AppIndicator precisa estar ativa para usar a bandeja. O teste na sua VM/outra partição, áudio e contas reais continua separado da validação automatizada. O Windows não é reinstalado por esta publicação.

## Build from source

Use the public main branch on Ubuntu 24.04 with Flutter 3.47.7/Dart 3.13 and the dependencies in `.github/workflows/ubuntu-preview.yml`. Run `flutter pub get`, `flutter analyze`, `flutter build linux --release`, then `bash scripts/package-ubuntu.sh`.

## Published package

[Download 2.5.5 Preview 1](https://github.com/eugilvando/Music-Time-Player/releases/tag/v2.5.5-ubuntu-preview.1). [Ubuntu CI](https://github.com/eugilvando/Music-Time-Player/actions/runs/41329999422): 101 targeted tests, analysis, release build, apt installation and controlled graphical checks passed; six screenshots reviewed. Runtime acceptance in your VM remains pending. SHA256: `32af5d2a8fadbb6d88997342c76a8b8a803561fd95dcb8b5f3c5fc79ce10df62`.
