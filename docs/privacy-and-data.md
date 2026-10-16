# Privacy, data and recovery

Music Time runs locally, without a Music Time backend. The installed app creates its own profile; no demonstration catalog or personal developer database is bundled.

## Storage

- The Windows application profile is normally under `%APPDATA%\com.example\Music Time`.
- SQLite stores the catalog, references, artwork, playlists, favorites, history, queue, managed download/cache state and supported application data.
- Preferences store interface and source configuration. OAuth sessions/server secrets use the system secure-storage integration, not a shared repository config.
- Explicit downloads and automatic audio cache occupy local disk separately from original music. Artwork is shared by content hash, but large collections and cover images still consume space.
- Build output, account configuration, provider credential JSON, databases, caches, personal backups and logs are excluded from this public repository.

## Network access

Connecting a source contacts the provider/server you selected. Microsoft/Google authentication opens their browser pages and receives a loopback callback. Synchronization reads the selected scope; playback/downloads can request audio and artwork. Source credentials must not be sent to issue trackers or chat.

Optional Last.fm requests can send the configured user profile and track/artist/album information; authorized now-playing/scrobbles send listening metadata. Artist portraits/biographies query TheAudioDB by artist name. Optional LRCLIB fallback queries music metadata to find lyrics. Those services have their own policies and availability. These integrations can be left unconfigured or disabled where exposed in Settings.

Offline mode prevents new remote audio resolution/transfers and restricts playback to available files. It is a playback/availability control, not a general-purpose firewall or a promise to block every unrelated network operation in the process.

## Catalog changes and deletion

Editing metadata, merging catalog entities, hiding a source and removing playlist occurrences do not rewrite, rename or delete original music. Removing managed downloads/cache is different from deleting original files. Reset and restore are explicit maintenance operations with confirmations; read their dialog carefully.

## Backups

The versioned JSON backup supports catalog data, embedded/shared artwork representation, manual metadata, playlists, favorites, listening history, queue/position and approved preferences, up to **128 MB**. It excludes credentials, provider-private configuration, physical music, audio downloads/cache and some separate artwork files. It cannot reconnect a provider or recover an original audio file by itself.

Restore replaces the supported data and preserves current provider credentials/configuration according to the app's contract. Reset clears recognized application-managed data, preserving originals. Filesystem, SQLite and secure storage are not one universal transaction. Keep your own copies of original music and export a backup before destructive maintenance.

The current database/backup schema is **16**. Older executables may not understand it. Do not run an older version against the only copy of a newer profile. For an offline physical profile snapshot, exit from the tray first and preserve the complete relevant profile and database auxiliary files consistently; a full snapshot restoration also reverts later changes.

## Reporting an issue

Include Windows version, Music Time version, source type, steps, a sanitized error message and the audio container/codec when known. Remove tokens, client secrets, authorization URLs, server passwords, local usernames, personal music paths and private account details before attaching diagnostics. This release does not yet provide a complete sanitized diagnostic-export workflow.

[README](../README.md) · [Provider setup](provider-setup.md)
