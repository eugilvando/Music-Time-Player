# Music Time 2.2.0+47

24 October 2026 · Windows x64

## Listening Insights

A new destination below History shows personal Last.fm data independently of local history: track/artist/album rankings, listening activity, the top artist, previous-period comparison and weekly/monthly/yearly summaries. Select the last 7/30/90/180/365 days, all time or custom dates; the actual date range and data coverage remain visible.

Create a reviewed selection with most-played, balanced-artist or rediscovery criteria, a per-artist limit and optional offline-only tracks. Review missing/ambiguous catalog matches. **Save playlist** creates a manual playlist without playing; **Play now** starts a queue without saving a playlist. CSV export includes metadata and coverage, without credentials.

Requires a Last.fm username and API key in Settings → Integrations. Public reading does not require a scrobbling session. The report cache is separated by profile/period and available offline. Up to 250 pages are read per operation; larger histories show partial coverage and can be continued. PDF reports and automatically updated playlists are not included. See [the guide](listening-insights.md).

## Included refinements since 2.0

- Independent primary/secondary fonts, responsive settings spacing, Home controls and loading reuse.
- Artwork indicator positions, artist Top Tracks, album header sizing and a single playlist-track action menu.
- Classic, Vinyl, Minimalist, Cover Only and Lyrics Only models.
- Resizable Queue/Lyrics panels with independent persisted widths, and preserved window dimensions/state when restoring from the tray.

## Validation and download

338 tests passed in the complete suite (6m18s). The 15 Last.fm tests were repeated after final cancellation/cache guards and passed; these overlap the suite. Final analysis, Windows release build and native media/tray/window checks passed. Runtime source in this public snapshot is compared against the tested development copy. Public-copy analysis is recorded in [the manifest](../release/validation.json).

Installer: `MusicTime-Setup-2.2.0.exe` · 20,436,396 bytes.

SHA256: `316916254BF98F02B2C62FBAEDA12C4EC2FD263F7C90567744B99B12C6B1FA18`

Controlled tests and fictional screenshots do not establish real-account acceptance, universal codec/device support or service certification. Live Last.fm report verification remains pending. Each user supplies their own Google/Microsoft OAuth application registration; see [provider setup](provider-setup.md). No personal database, playlists, credentials, backups or SDK are included. Existing MIT and third-party licensing terms remain in effect.