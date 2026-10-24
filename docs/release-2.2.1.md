# Music Time 2.2.1+48

24 October 2026 · Windows x64

## Multi-disc albums

- Albums show Disc 1, Disc 2 and subsequent sections in detailed lists, compact lists and compact cards. Playback uses the complete album queue in disc/track order, including album cards on Home.
- MP3 TPOS and FLAC DISCNUMBER support number/total values, including spaces such as `2 / 2`. Files can share one folder or use explicit CD1/CD2, Disc, Disk or Disco subfolders.
- Folder fallback applies only when a valid disc tag is missing. Subfolders merge conservatively under a common parent when album title, album artist, year, edition, source and account match. Other editions remain separate.
- Original files and paths are unchanged. Track IDs, playlist occurrences, track favorites and previous album favorite/filter identities remain supported.

## Upgrade and cloud metadata

The first launch upgrades SQLite's derived catalog projection to schema17 in batches of 500 rows, without loading full artwork or recreating playlists/history. Logical backups remain schema16/container2. An older SQLite16 executable must not directly open a migrated database; returning requires a previous compatible backup or restore workflow.

For tracks already cataloged without disc tags, manually synchronize/reindex the source. OneDrive and Google Drive/WebDAV refresh old MP3/FLAC metadata once using reader revision3; known current revisions are reused. Optional read failures preserve previous metadata. No automatic personal scan is started by this update.

## Validation

The intermediate full run recorded 346 passes and two failures (album-card order and an outdated SQLite16 expectation). After final fixes, 50 targeted regressions passed, including both cases. This establishes 348 unique passing cases across overlapping runs; it is not a claim of one final clean full-suite run. The initial 26 targeted checks overlap these tests.

Final analysis, Windows release build (157.3s), native playback/media/artwork, tray, window-state and clean-exit checks passed. Public-snapshot comparison, analysis and repeated disc tests are recorded in [validation.json](../release/validation.json). Controlled tests do not establish acceptance on every personal library, codec or device.

Installer: `MusicTime-Setup-2.2.1.exe` · 20,438,357 bytes.

SHA256: `FDC0144871AF46CDA3C0584651D007A07E70E46493AA91B4F037947197CC8717`

Includes [Listening Insights from 2.2.0](release-2.2.0.md). Each user supplies their own Google/Microsoft OAuth application registration: [provider setup and limitations](provider-setup.md). No personal databases, playlists, credentials, backups or SDKs are published. MIT and third-party licensing terms remain in effect.

## Português brasileiro

Organização e reprodução por disco/faixa, com seções Disco 1/2 e suporte a faixas na mesma pasta ou CD1/CD2. Tags válidas têm prioridade; IDs, playlists e favoritos preservados. A primeira abertura migra apenas a projeção derivada para SQLite17. Backup lógico16/contêiner2 mantidos. Para recuperar números de disco ausentes no catálogo, sincronize/reindexe a fonte manualmente. Retorno a executáveis SQLite16 exige backup compatível anterior.
