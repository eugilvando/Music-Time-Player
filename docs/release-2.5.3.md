# Music Time 2.5.3+55

27 October 2026 · Windows x64

## Artist navigation and radio

- Clicking artist credits in the player bar opens the first album artist when present; otherwise the first track artist is used, including explicit credit lists. Displayed track credits stay unchanged. The correct artist group is matched by normalized name and role.
- Mix and radio actions are available for tracks, artist collections and albums (including Home cards, catalog menus, track/queue menus and context actions). All creation uses Last.fm data first, including useful saved data. If there are no usable recommendations/matches, local credits/genres are used automatically. An eligible seed starts the queue; pools are never padded.
- Artist mix/radio candidates come from all visible library sources, respecting availability and offline mode, instead of being accidentally restricted by the current page search/filters. Artist mixes emphasize the seed artist while including related artists; radios interleave the seed artist and known similar artists with eligible tracks.
- Case and whitespace variants follow the existing catalog identity. Accents/punctuation remain significant; no fuzzy homonym merging. The selection builds an artist index instead of repeatedly scanning the catalog. Small pools are not padded with repetitions or invented tracks.
- Similarity cache lasts seven days for nonempty results and fifteen minutes for empty results. Refresh Last.fm bypasses freshness. Empty/error replies preserve useful older data; malformed cache can recover. An optional cache-write failure does not discard valid remote data.
- Queries allow twelve seconds per attempt and one retry for timeout or transient Last.fm errors 11/16. No automatic retry for invalid keys or rate limit 29. Duplicate equivalent requests are coalesced; offline reads never join pending online requests.
- Preview shows similar-artist and eligible-library counts, cached status and distinct missing-key, network, offline or no-result messages. Regenerate reuses cached similarity; Refresh Last.fm forces a fetch.
- Last.fm recommendations are the default for both mix and radio. If unavailable or unmatched, local genres/credits are used automatically. If no local related tracks exist, the available seed artist/items form a local mix. Actual source/mode is labelled in preview and queue title; no extra fallback choice is required. Selection/local matching run in an isolate; late results cannot apply after closing or superseding a request.
- Play starts a named queue. Saving a playlist always requires an explicit save action. Existing playback continues while the preview loads.

SQLite18, logical backup17 and container2 are unchanged. No new migration. The existing similarity-cache table is reused. Names shared by real homonyms remain a limitation; no real personal Last.fm account acceptance was performed.

## Validation

Dependency resolution, formatting and direct Dart analysis passed. 32 targeted cases passed in the final run, covering navigation, selection, cache/refresh, malformed-cache recovery, missing keys, retry, online/offline isolation, local queue generation, existing mix/radio UI, player bar and multi-screen layouts. Eleven new cases were repeated in the public copy. Windows build and isolated native media/artwork, tray, vault, styles, placement and clean exit passed. Source/package hashes are in [validation.json](../release/validation.json).

Personal installation awaits confirmation; the owner's installed application was not replaced during validation/publication. No personal data or backups published. Ubuntu Preview 2.4.1 is unchanged.

Installer: `MusicTime-Setup-2.5.3.exe` · 20544066 bytes.

SHA256: `7A7DB2D058714A0673F411A05585A0FFDC3CF6182537FC8F1B1C35E5CDD2F601`

Users supply their own OneDrive/Google Drive application registrations: [provider setup and access limitations](provider-setup.md).

## Português brasileiro

Clique do artista na barra prioriza artista do álbum; rádio/mix com identificação consistente, cache e diagnósticos melhores, renovação Last.fm e fallback local automático. Reproduzir inicia fila; playlist só com ação explícita. 32 testes finais e onze casos novos repetidos na cópia pública. Análise/build/nativo aprovados; instalação pessoal aguarda confirmação. Sem nova migração, dados pessoais publicados ou atualização Ubuntu. Aceite na conta real Last.fm permanece separado.
