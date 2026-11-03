# Music Time 2.8.0 — Ubuntu 24.04 x64

The Ubuntu package now includes the artist-ranking and queue improvements already delivered on Windows:

- Artist-only mixes prioritize global Last.fm top tracks available in your library, with local play-count fallback. Track and album entry points follow the same rule; compilations allow choosing an artist. Radio retains its similarity behavior.
- Artist pages show up to 20 Top Tracks. Drag each track to the queue or use the icon-only Play and Shuffle actions for the displayed list.
- Reorder queue tracks by dragging the row content, without needing a drag handle.
- Retains album drag, automatic/manual crossfade, AutoEQ text import and per-output EQ profiles, Last.fm favorites, mood playlists and the prior desktop integrations.

## Install or upgrade

Close Music Time using tray → Exit, then install the attached package with:

```sh
sudo apt update
sudo apt install ./music-time-preview_2.8.0-0ubuntu1_amd64.deb
```

The internal package name `music-time-preview` and application identifier remain unchanged so apt upgrades existing installations and uses the existing profile. This is a final release, not a preview designation. Back up your profile before upgrading.

## Validation scope

The accompanying validation manifest records the matching Ubuntu CI run, test count, package installation, graphics checks and SHA256. Native playback tests use virtual audio in CI. Real speaker/headphone output, output switching, GNOME AppIndicator behavior and live cloud accounts still require validation in the user's VM or Ubuntu partition. Windows 2.8.0 remains the latest Windows release.