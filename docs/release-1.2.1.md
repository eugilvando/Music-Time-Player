# Music Time 1.2.1

Release date: **2026-10-16**. Application/build version: **1.2.1+41**. Windows x64; database schema16; backup schema16.

## This release

- Playlist repair controls automatically disappear after the last missing reference has been linked or removed.
- Leaving the missing-only state restores the complete playlist view.
- Includes the existing artist mix/radio, multi-file M3U8 import and all current features described in the [README](../README.md).

This is the initial public snapshot, with a new repository history. The runtime code is copied from the validated current application. Public packaging adds documentation, MIT licensing for Music Time's code, third-party notices, fictional demonstration screenshots and portable test-font resolution. The application runtime does not receive new features under the same version number.

## Validation

The application baseline passed **297 tests**, Dart analysis, a Windows release build and isolated native playback/media/tray/data restart checks. The public snapshot is additionally checked before publication; `release/validation.json` records the publication checks without private logs or account data.

The Windows release uses the validated 1.2.1 application binaries. Public packaging replaces the root native-assets build metadata with the portable manifest already included in the application bundle, removing developer-machine paths. The installer also adds notices and license information; its checksum can differ from the developer's earlier private package. Download the installer and compare it with the release's `SHA256SUMS.txt`.

## Before connecting

Local playback needs no account. OneDrive personal and Google Drive require **your own Client ID/application registration**; there is no universal built-in provider login. See [setup and limitations](provider-setup.md). Real account/server/device validation remains narrower than controlled tests.

The installer is unsigned. No SDK or music content is bundled. Last.fm, metadata and lyrics services are optional and require their own availability/configuration. See the README for the full current limitations.

[Download release](https://github.com/eugilvando/Music-Time-Player/releases/tag/v1.2.1) · [README](../README.md)
