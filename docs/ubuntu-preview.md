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
