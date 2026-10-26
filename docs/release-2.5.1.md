# Music Time 2.5.1+53

26 October 2026 · Windows x64

## Home caching and background refresh

- Home reuses the last prepared composition when revisiting the page during the same app session. Stable revision/filter keys avoid regenerating mixes just because a temporary catalog index was recreated.
- When data changes, compatible content remains visible with a small progress indicator. New results replace the composition together only after processing completes. Stale responses are discarded and concurrent work remains bounded.
- Small libraries also refresh in the background when prior content exists. Initial small-library preparation remains immediate; initial large-library preparation keeps its skeleton.
- Two compositions at most are cached in memory. This does not persist a second catalog or credentials to disk. The first Home composition after restarting the app is rebuilt from the local database; this differs from the persistent report cache in Insights.
- Removed/hidden tracks and incompatible filter/offline scopes invalidate the old composition instead of displaying tracks outside the current selection. Preparation failures preserve compatible content and allow retry. Manual mix regeneration remains available.

SQLite18, logical backup17 and container2 are unchanged. No new migration or changes to original music files. Ubuntu Preview 2.4.1 is unchanged; this release only updates Windows.

## Validation

Dependency resolution, formatting and direct Dart analysis passed. 19 targeted tests passed in the final run: Home cache/revisit/background replacement/filter safety, existing Home/mix/layout behavior, migration, playlist favorites and 30,000-track background catalog preparation. Three cache regressions were repeated in the public copy. Windows build and isolated native media/artwork, tray, vault, window-placement and clean-exit checks passed. Source hashes and installer digest are in [validation.json](../release/validation.json).

The final Windows build was installed locally after a private rollback backup; executable/app.so match, with database, preferences and credential-store files unchanged by hash. No personal data or backups are published.

Installer: `MusicTime-Setup-2.5.1.exe` · 20486947 bytes.

SHA256: `3D3288CDE75BC9FA02D29214CF2499FC1D23FD64E144953AB2D827AB4D0C19D0`

Users supply their own OneDrive/Google Drive application registrations: [provider setup and access limitations](provider-setup.md).

## Português brasileiro

Home com cache de sessão e atualização em segundo plano, sem apagar o conteúdo compatível durante o carregamento. Fontes ocultas/removidas e filtros offline não reaproveitam conteúdo incompatível. 19 testes na execução final; três repetidos na cópia pública, análise/build/nativo aprovados. Dados preservados. Sem nova migração; Ubuntu inalterado.
