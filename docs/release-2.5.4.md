# Music Time 2.5.4+56

30 October 2026 · Windows x64

## Library synchronization and visibility

- A completed OneDrive scan retires items missing from the scanned account/folder. Catalog queries respect this exclusion even when the source is active. Other cloud/server sources also retire absent items after completed scans. Renamed stable IDs update in place; rediscovered items become available again.
- Seen/checkpoint identities use the actual persistent catalog IDs. Personal OneDrive account IDs differing only in hexadecimal letter case preserve track identity and playlist references instead of accidentally retiring found tracks.
- Cancellation, authentication/network failures and inaccessible folders do not complete absence reconciliation. Original music files are preserved. Missing records are retained as catalog tombstones to preserve playlist identity; they are not listed as available library items. Run a source synchronization after updating to reconcile an existing collection.
- Track details show the selectable persistent source folder/file location rather than a temporary playback URL.
- Hide/show actions are available for tracks, selections and collections. Collection actions affect the collection's selected tracks. Library filters offer Visible items (default), Include hidden items and Hidden items only, persisted by category.
- Manual hiding survives source rescans, metadata edits, restoring original tags and restart. It preserves original files, downloads, favorites and existing playlist/queue occurrences. Normal library queries, Home and global search exclude hidden items. The hidden filter does not reveal absent-source tombstones or disabled sources.
- Sidebar ordering uses drag handles, switches and movement menus matching the player bar organizer. Existing order and visibility preferences remain intact; Settings stays in the footer. Catalog information editing is last in the track menu; album metadata editing is last in album-page actions.

SQLite18, logical backup17 and archive container2 are unchanged. No schema migration.

## Validation

51 targeted regressions passed in the final run, plus one package/About version check. Direct Dart analysis and formatting passed. Coverage includes complete/cancelled/failed scans, scope/account boundaries, persistent IDs, renamed/reappearing items, hidden-item persistence, SQL/in-memory parity, playlist repetitions/favorites, sidebar controls, catalog pagination and Home cache. Public-copy checks are recorded in [validation.json](../release/validation.json).

Windows release build passed (253.4 seconds). Isolated native checks passed for artwork, media controls, tray, styles/session, restored window placement and clean exit. Installer creation and the owner-authorized local update passed; existing data was preserved. Personal collection acceptance still requires a completed source scan after installation. No personal profiles, credentials or backups are published. Ubuntu Preview 2.4.1 is unchanged.

Installer: `MusicTime-Setup-2.5.4.exe` · 20547196 bytes.

SHA256: `8DFADAAA271531139F9DE1BD491C21627D4EBD461BCB04DB7DF4BAD041123992`

Users provide their own OneDrive/Google Drive application registrations: [provider setup and access limitations](provider-setup.md).

## Português brasileiro

Sincronização concluída retira faixas ausentes do catálogo; caminhos renomeados e identidades OneDrive são preservados corretamente. Detalhes mostram caminho na fonte. Ocultar/reexibir itens com filtros persistentes, sidebar com arraste e edição no final das ações. Em coleções, ocultar afeta as faixas da seleção. Arquivos, favoritos e playlists existentes são preservados. Após atualizar, sincronize a fonte para conferir a coleção real. 51 regressões e uma conferência de versão aprovadas, análise/build/nativo/instalador aprovados. Instalação pessoal concluída; Ubuntu inalterado.
