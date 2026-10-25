# Music Time 2.4.1+51

25 October 2026 · Windows x64

## Queue and settings

- **Save queue as playlist** and **Clear queue** are in the action menu beside the Queue panel title, including smaller-window drawer navigation. Saving preserves the full order and repeated occurrences. Empty-queue actions are disabled; clearing remains unavailable while a track is opening.
- Settings → Interface and player: **Sidebar** and **Organize player bar** are collapsible, initially closed. Expanding/collapsing does not change saved item order or visibility.
- All 2.4.0 features remain available. SQLite18, logical backup17 and archive/container2 are unchanged.

## Validation

17 targeted tests passed: queue menu and saving repeated tracks, organizer expansion/collapse, order/visibility controls, persistence and related Insights/reference-review regressions. Analysis passed, Windows release build and isolated native playback/artwork, tray, window-placement and clean-exit checks passed. Ten overlapping focused cases were repeated in the public copy; source hashes and installer digest are recorded in [validation.json](../release/validation.json). This revision did not rerun the full suite; see [2.4.0](release-2.4.0.md) for the preceding full-suite evidence. No personal catalog, credentials or backups are published.

Installer: `MusicTime-Setup-2.4.1.exe` · 20476470 bytes.

SHA256: `7BEE3B7DF65BB624F848F23B2477B67767BC8C534DB473B9C40EAEB668F698ED`

The Ubuntu preview is unchanged and remains separate. Users supply their own OneDrive/Google Drive application registrations: [provider setup and access limitations](provider-setup.md).

## Português brasileiro

Salvar fila como playlist e Limpar fila ficam no menu de ações junto ao título de Queue. Os organizadores da sidebar e da barra de reprodução são recolhíveis e começam fechados. Preferências e dados preservados; 17 testes direcionados, análise/build e verificações nativas aprovados. Dez casos sobrepostos repetidos na cópia pública. Sem nova suíte integral; Ubuntu inalterado.
