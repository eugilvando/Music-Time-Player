# Music Time 2.3.0+49

25 October 2026 · Windows x64

## Album metadata and artwork

Open an album and use its action menu: **Review album metadata**, **Choose album cover**, or **Restore source cover**. Review album title, album artists, genres, year and edition across all current tracks of that album, even when its quick track filter is active. Only checked fields are applied; mixed values start unchecked. A checked empty field clears that value. Individual track titles, track credits, duration, disc/track numbers, IDs, file paths and playlist references are preserved. Changing collection identity can require favoriting the collection again; track favorites remain by ID.

Choose a PNG/JPEG up to 4 MiB, including for albums without artwork. The app validates it and stores a normalized PNG up to 1024 px per side, once per hash. Manual artwork is separate from the source image and survives synchronization, tag reset and artwork optimization. Restore source cover removes only the manual selection. Include Library + Artwork when exporting it in a backup. Newly added tracks do not automatically inherit a previous bulk edit. Original music files are never retagged or rewritten.

## Memory use

- Artwork and portraits decode to physical display-size buckets (64–2048 px), including display scaling. Larger player artwork retains a larger variant and image proportions are preserved.
- Decoded-image cache budget: 64 MiB/400 entries, previously 100 MiB/1,000. Compressed catalog artwork: 8 MiB/96 entries, previously 16 MiB/128.
- Completed portrait reads: 8 MiB/64 entries, previously retained without a session limit. In-flight requests remain shared; invalidated late responses cannot repopulate the cache. Disk/custom images are preserved.
- Home retains two derived results and collection browsing three, preserving current content during background preparation. Audio buffer settings are unchanged.

Controlled PNG fixture: a 2048×2048 image uses 16,777,216 decoded pixel bytes; a 96 px thumbnail at DPR1 uses a 128 px variant, 65,536 bytes. The large variant remains 2048 px. This is one image measurement, **not total process RAM or a personal-library before/after benchmark**. Cache budgets are not a hard application RAM limit.

## Compatibility and validation

Runtime SQLite18 installs a trigger protecting artwork referenced by manual cover metadata, including against legacy cleanup SQL. The version number alone does not prevent every old executable from opening the database; downgrading is unsupported without restoring a prior compatible profile copy. The migration from SQLite17 preserves track IDs and playlists. Logical backups use schema17/container2 and still read supported older documents; older parsers reject new schema17 backups. Keep a compatible copy before upgrading.

355 tests passed in the final full run; final analysis, Windows release build and isolated native Windows integration checks passed. Public source comparison, repeated focused tests and installer digests are recorded in [validation.json](../release/validation.json). Earlier incomplete runs identified test-environment/compatibility expectations that were corrected; overlapping repetitions are not additional unique cases. Controlled tests do not establish acceptance for every library, codec or device.

Installer: `MusicTime-Setup-2.3.0.exe` · 20450146 bytes.

SHA256: `6BECFC326018381652BC6B6055EF9B5BF4656730F64F4D5DBD81A1C383C34A7F`

The separate Ubuntu 2.2.1 preview is unchanged. Each user supplies their own Microsoft/Google OAuth application registration: [provider setup and limitations](provider-setup.md). No personal databases, credentials, playlists, backups or SDKs are published. MIT and third-party terms remain in effect.

## Português brasileiro

No menu de ações do álbum, revise os campos comuns de todas as faixas, escolha uma capa ou restaure a imagem da fonte. Somente campos marcados são aplicados. Arquivos originais, títulos/créditos individuais, duração e ordem disco/faixa são preservados. Capas manuais persistem na sincronização e podem ser exportadas selecionando Biblioteca + Capas no backup. Miniaturas decodificadas por tamanho e caches limitados reduzem memória de imagens; não foi medido o consumo total antes/depois na coleção pessoal. SQLite18/backup17/contêiner2; retorno requer cópia anterior compatível. Ubuntu continua uma prévia separada.
