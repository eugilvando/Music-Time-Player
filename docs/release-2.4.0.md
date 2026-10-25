# Music Time 2.4.0+50

25 October 2026 · Windows x64

## Listening Insights playlist templates

In Listening Insights → Create a playlist, choose Artist radio, Artist most played in the selected period, or Artist most popular on Last.fm (global). Choose an artist from the suggestions and review the generated selection before saving a manual playlist or starting a queue. Only library track IDs are saved; no outside music is downloaded. Track limits are 10/20/30/50/100. Existing balanced, most-played and rediscovery templates remain available.

Artist radio uses Last.fm similar names and round-robins tracks from the seed and similar artists present in the library. It requires the seed and at least one similar artist with catalog tracks. Personal artist ranking uses only the loaded report and retains its incomplete-history notice. Global popularity reads up to 200 artist top tracks, matches title/artist against the catalog, and keeps ambiguous recordings for explicit review. It is not your personal listening count. These are snapshots, not automatically updating smart playlists.

Global artist rankings cache for seven days, retain at most 50 artist payloads and share active requests. Similarity reuses the existing cache. Offline mode uses cached service data and available library tracks; missing cached data cannot generate a remote ranking. API/settings/service failures are surfaced without silently saving a different template. Artist portraits use the same library component, customized images, cache and artwork fallback.

## Queue and reference review

The queue panel adds **Save queue as playlist**. It snapshots the queue at the time of the action and preserves its complete order and repeated occurrences; it does not start playback. Original files stay unchanged.

Playlist import, pending references and Last.fm matching show the expected title/artist. Suggestions consider existing candidates, filename, title, artist and available duration, and are calculated in an isolate. A suggestion never confirms itself. Check live/remix/instrumental editions and confirm the intended recording; the original reference remains available.

## Interface and player

- Settings → Interface and player → Sidebar: move items up/down, enable/disable them and restore defaults. Applies to expanded, collapsed and drawer navigation. Settings remains accessible in the footer; the logo still opens Home. Preferences persist and are included in backups.
- Artwork scale extends to 2.6. Vinyl can use more width and its natural aspect ratio, while reserving room for track information and respecting smaller windows.
- Lyrics font extends to 80; line-height control extends down to 0.8, with smaller inter-line padding. 
- English and Brazilian Portuguese labels are included.

SQLite18, logical backup17 and archive/container2 remain unchanged. Existing preferences are preserved; older executables may reject backups containing the new sidebar lists or expanded numeric ranges. Keep a previous compatible profile copy for rollback. No personal account scan or source-file modification is part of the update.

## Validation and package

362 tests passed in a clean full suite. A final portrait adjustment then passed eight focused Insights tests and final analysis. Analysis, Windows release build and isolated native media/artwork, tray, window placement and clean-exit checks passed. Public source comparison, repeated focused checks and digests are recorded in [validation.json](../release/validation.json). Controlled service responses verify implementation; personal Last.fm acceptance remains a separate user check. No personal profiles, credentials, playlists or backups are published.

Installer: `MusicTime-Setup-2.4.0.exe` · 20477295 bytes.

SHA256: `68656070BA6B4E920F2AC50789C63800F0B5BF1FB2F2D57CF99893D663C4FC84`

The separate Ubuntu 2.2.1 preview is unchanged. Each user supplies their own provider registration: [setup and limitations](provider-setup.md). MIT and third-party terms remain in effect. Primary API contracts: [artist.getTopTracks](https://www.last.fm/api/show/artist.getTopTracks), [artist.getSimilar](https://www.last.fm/api/show/artist.getSimilar).

## Português brasileiro

Novos modelos em Insights: rádio do artista, mais ouvidas no período e popularidade global, sempre cruzados com a biblioteca e revisados antes de salvar/reproduzir. Salvar fila preserva ordem e repetições. Importações e Last.fm exibem a faixa esperada e sugestões sem substituição automática. Barra lateral configurável em Interface e player, retratos iguais aos da biblioteca, vinil maior, letras até 80 e altura de linha mínima 0,8. Dados e preferências anteriores preservados; backup privado anterior à instalação. Aceite com conta pessoal separado dos testes controlados. Ubuntu continua prévia separada.
