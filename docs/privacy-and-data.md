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

The new .mtbackup archive lets you choose library data, playlists, favorites, history, queue/position, preferences, artwork and source application IDs. Import merges selected data; playlist imports add copies and preserve order/repetitions. Missing or ambiguous references stay available for review. Legacy JSON files remain readable.

Credentials and sessions are optional and require source settings plus a password of at least 12 characters. Encryption uses AES-256-GCM with a random nonce/salt, authenticated header and PBKDF2-HMAC-SHA256 (600,000 iterations). Passwords are not saved or recoverable. Decrypted credentials are not staged in temporary files; imported sessions are stored in the system vault. A source can still require reconnection after expiration or on another machine. Restart after importing source/session settings.

Music files, audio downloads/cache and separate custom-artwork files are not included. Artwork is omitted by default; select it explicitly when needed (64 MiB preflight cap, including legacy images). The decompressed archive limit is 128 MiB. See [backup instructions](backup.md).

Reset still requires three confirmations and preserves original music. SQLite, preferences, secure storage and filesystem are not one universal transaction. Keep separate copies of original music.

The runtime database schema is **18**; logical backups use schema **17**, archive/container **2**. Manual catalog artwork references are protected by a database trigger and preserved by current cleanup. Older executables do not understand the feature; the version number alone does not block all older database opens. Downgrade requires a previous compatible profile copy. New schema17 backups are rejected by older parsers. Include Library + Artwork to export manual album covers. For an offline physical profile snapshot, exit from the tray first and preserve the complete relevant profile and database auxiliary files consistently; a full snapshot restoration also reverts later changes.

## Reporting an issue

Include Windows version, Music Time version, source type, steps, a sanitized error message and the audio container/codec when known. Remove tokens, client secrets, authorization URLs, server passwords, local usernames, personal music paths and private account details before attaching diagnostics. This release does not yet provide a complete sanitized diagnostic-export workflow.

[README](../README.md) · [Provider setup](provider-setup.md)

## Listening Insights cache and exports

Listening Insights stores bounded derived reports by Last.fm profile and period in the local database, separately from local listening history. The cache is excluded from backups and discarded on restore/reset. CSV export is explicit and contains profile name, listening metadata, date ranges and coverage, without API keys or sessions. Generated playlists store references to tracks already in the user's library. No report is uploaded to a Music Time server.
