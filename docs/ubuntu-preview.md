# Music Time 2.6.1 — Ubuntu 24.04 x64

This is the final Ubuntu release based on 2.6.1+58. The existing Debian package name `music-time-preview`, launch command and `app.musictime.preview` application identifier are retained so apt upgrades the installed preview and finds its existing profile. The application displays Music Time.

## Install or upgrade

Close Music Time, back up your Linux profile, and download the .deb and SHA256SUMS.txt from the Ubuntu release.

```sh
sha256sum -c SHA256SUMS.txt
sudo apt update
sudo apt install ./music-time-preview_2.6.1-0ubuntu1_amd64.deb
music-time-preview
```

## Features and scope

Drag library tracks into the queue. Choose autoplay behavior through the existing Continuous play button or Playback settings. Create genre and mood playlists through Insights and Last.fm tags. Playback settings include Crossfade, Smart fades and Mix only.

Smart fades currently analyzes local 16-bit PCM WAV envelopes and uses the configured duration for other formats. Mix only requires supported local analysis and a disabled equalizer. Sequential album playback bypasses overlap. Last.fm/community tagging and real cloud delivery require account acceptance.

Ubuntu needs an active AppIndicator extension for the tray. The package recommends it and the app checks for a host before hiding. Verify close, minimize, restore, playback and Exit in your desktop session. Re-pin an older launcher if its icon is stale.

## Graphics and validation

Default compatibility rendering uses X11 and Mesa software OpenGL with Impeller disabled. After closing the app, use `MUSIC_TIME_RENDERER=software music-time-preview` for CPU rendering or `MUSIC_TIME_RENDERER=hardware music-time-preview` for a hardware comparison.

The release manifest records the CI run, tests, package checksum and graphical inspection. Real speaker output, cloud accounts, GNOME tray interaction and your VM/partition require separate acceptance. Native overlap tests have Windows coverage. The final release designation was requested by the project owner.

## Português

Versão final 2.6.1 para Ubuntu 24.04 x64. Atualize com o comando apt acima. O identificador interno conserva a palavra preview para atualizar a instalação existente e preservar o perfil. Confira bandeja, áudio e contas reais na sua VM/outra partição. As limitações de Smart fades e Mix only estão descritas acima.
