# Music Time 2.5.2+54

26 October 2026 · Windows x64

## Shuffle and interface

- Shuffle still rearranges the visible queue. Turning it off restores the pre-shuffle order while keeping the current occurrence, audio and position. Repeated tracks stay distinct. Removed occurrences do not return; new tracks join the original order at the end or after the current track when added with Play next. Manual reordering while shuffled affects that visible shuffled sequence; turning shuffle off restores the baseline with additions/removals applied.
- Original positions are saved locally and validated against the exact saved queue and a complete position permutation. Mismatched/invalid snapshots are ignored. Older sessions have no pre-shuffle snapshot and use the restored visible order as the initial baseline. The auxiliary snapshot is not part of selective logical backups. No new database migration.
- Settings adds About: application version/build, Gilvando Souza attribution, personal design engineering/AI context, GitHub source, releases, issues, MIT/third-party licensing, technology stack, local data and provider setup. External links show a recoverable message if the browser cannot open; URLs remain selectable. Portuguese and English supported.
- The collapsible Sidebar organizer sits directly below Navigation and Home under Interface and player; existing preferences are preserved.
- The Home/Now Playing artwork backdrop is now shared by all sections, using the same mode and intensity settings. Cards and panels retain their surfaces. Solid mode and missing artwork remain supported.

## Validation

Dependency resolution, formatting and direct Dart analysis passed. 20 targeted tests passed, covering occurrence-safe shuffle restoration, additions/removals, validated session snapshots, About version consistency and English/Portuguese layouts at small width with enlarged text, existing queue/navigation/Insights/settings behavior and all-screen layout regressions. Six overlapping new cases were repeated in the public copy. Windows release build and isolated native media/artwork, tray, vault, styles, window placement and clean exit passed. Source and package hashes are in [validation.json](../release/validation.json).

This revision was published before updating the owner's installed app, as requested. Personal installation awaits their confirmation after exiting the tray. No personal data or backups are published. Ubuntu Preview 2.4.1 is unchanged.

Installer: `MusicTime-Setup-2.5.2.exe` · 20535696 bytes.

SHA256: `95ED148D2E43B484AA8BE9306AF9BB7AB36FC5D535C397839B8A8FCDA368AC88`

Users supply their own OneDrive/Google Drive application registrations: [provider setup and access limitations](provider-setup.md).

## Português brasileiro

Shuffle restaura a ordem anterior ao desativar, mantendo a faixa atual. Fundo global; página Sobre; organizador da sidebar abaixo de Navegação e início. 20 testes direcionados aprovados, seis repetidos na cópia pública; análise/build/nativo aprovados. Instalação pessoal aguarda confirmação; nenhum dado pessoal publicado. Sem nova migração; Ubuntu inalterado.
