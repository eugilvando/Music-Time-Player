# Music Time 2.5.0+52

26 October 2026 · Windows x64

## Queue, navigation and loading

- Shuffle rearranges the actual queue while preserving the current occurrence and playback position. Next/previous and preloading follow the displayed order. Duplicate occurrences remain distinct. Disabling shuffle keeps that order; queue repeat uses the same visible sequence. Session restoration stays paused and preserves the saved order.
- The player bar wraps enabled controls on narrow windows instead of clipping the right edge. Very short windows or large text use a capped height with vertical scrolling. Saved item order/visibility remain unchanged.
- Volume button and slider are 8 px apart. Active Last.fm uses its brand red, #d1170e.
- Home uses an initial loading skeleton and respects reduced motion. Existing content remains visible during background refresh.
- A–Z navigation beside name/title-sorted Library, Albums, Artists and Playlists works with lists, grids and detailed tables. Accent folding and # are supported. SQL-paged tracks jump to the appropriate page using the current filters without loading the full result.
- Listening Insights immediately reuses saved reports, refreshes automatically once per account/period selection per app session, and retains the previous content while loading. Manual refresh remains available; absent/evicted cache can be fetched again. Account, update time and refresh share the period toolbar, with responsive stacking in smaller windows.

SQLite18, logical backup17 and container2 are unchanged. No new data migration. No personal catalog, credentials or backup is included.

## Validation

Offline dependency resolution, formatting and direct Dart analysis passed. The broad development run passed 368 cases with three intermediate failures; after fixes, all 20 final regression cases passed, covering those failures, every page at multiple sizes/scales, narrow player layouts and cached Insights. This represents 371 unique cases passing across complementary runs, not one final full-suite run. Eight overlapping regression cases were repeated in this public copy. Source hashes, installer and native binary digests are in [validation.json](../release/validation.json).

Windows release build and isolated native playback/artwork, media controls, tray, vault, window placement and clean exit checks passed. The final installer was installed locally with matching executable/app.so and unchanged database, preferences and credential-store hashes. Personal Last.fm account acceptance remains separate.

Installer: `MusicTime-Setup-2.5.0.exe` · 20484653 bytes.

SHA256: `F97F4BA40626356764E5B357BBD8AAF1BD92A02E49ECA9B08349ABE586DC40B6`

This release contains only the Windows update. Ubuntu Preview 2.4.1 is unchanged. Users supply their own OneDrive/Google Drive application registrations: [provider setup and access limitations](provider-setup.md).

## Português brasileiro

Fila embaralhada visível, barra adaptativa, volume com 8 px, Last.fm vermelho, skeleton da Home, A–Z e cache/atualização em segundo plano nos Insights. Banco, preferências e credenciais preservados na instalação. 371 casos únicos aprovados em execuções complementares, com 20 regressões finais e oito casos sobrepostos repetidos na cópia pública. Build e integração nativa aprovados; sem nova migração. Esta atualização é apenas Windows; Ubuntu inalterado.
