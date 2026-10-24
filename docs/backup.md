# Backup and selected import — 2.0

Open **Settings → Backup and advanced**.

## Export

1. Choose Export backup and select the data to include.
2. Artwork is optional and unchecked initially. Music files and physical downloads/cache are never copied.
3. Select Sources and application IDs to retain your own provider registration and folder configuration.
4. Credentials/sessions are optional. Selecting them requires source settings and password encryption. Use at least 12 characters and keep the password separately: Music Time cannot recover it.
5. Save the .mtbackup file. Encoding, compression and encryption run in a worker isolate. The expanded limit is 128 MiB; artwork is checked before loading (64 MiB). If too large, export without artwork.

## Import

1. Choose Restore backup and open .mtbackup or a supported legacy JSON.
2. Enter the password locally when required.
3. Select what to import. You can select **only Playlists** to preserve the current library and preferences.
4. Continue to merge the selected data. Existing unrelated catalog items remain; selected matching library metadata can be updated. Playlists are added as copies, retaining order and repeated tracks. Track matching uses existing identity, cloud drive/item or local path; missing/ambiguous entries remain reviewable.
5. Queue restoration starts paused. Restart before using imported provider configuration or sessions. Authorization may still be required after expiration or on another computer.

The new archive can include secrets only through AES-256-GCM encryption (PBKDF2-HMAC-SHA256, 600,000 iterations, random salt/nonce and authenticated header). Secrets are never stored in a plaintext maintenance request. SQLite, preferences and system vault do not form a universal transaction; keep a separate recovery copy before substantial changes.

The archive does not include your original music, managed audio files, sync cursors, scrobble outbox or separately stored custom images. It cannot recreate missing audio by itself. Older releases cannot read .mtbackup; retain an older compatible physical snapshot when rollback is required.

[README](../README.md) · [Privacy and data](privacy-and-data.md)
