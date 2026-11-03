# Music Time 2.8.0 — Windows

Artist mixes now use the artist's global Last.fm top-track ranking, matched to eligible tracks in your own library. Missing entries are filled using local play counts; unavailable Last.fm data falls back to saved ranking data or local history. Track and album entry points follow the same artist-only rule. Compilations without a single artist ask you to choose one. Mix playback starts in ranking order, independently of the previous shuffle setting.

The radio mode retains its current similarity selection and fallback behavior.

Artist pages show up to **20 Top Tracks**, using the same Last.fm-first/local-fallback ranking. Drag an individual featured track into the queue, or use the icon-only **Play** and **Shuffle** buttons beside the section heading to play the displayed selection.

Reorder the queue by dragging a row's artwork, text or empty space, without needing the drag handle. Clicking a track and using its action button continue to work.

## Scope

- Rankings refer to global artist popularity, not the user's personal Last.fm listening chart. They are cached; the mix dialog's Refresh Last.fm action requests a fresh ranking. Local fallback uses actual recorded play counts, then a stable title/ID tie-break.
- Only visible, available library tracks are selected; offline eligibility is preserved. Guest and album-artist credits follow the catalog's existing artist matching. Missing songs are not streamed from Last.fm. Duplicate editions use local plays to choose a deterministic ranking match.
- [Last.fm artist.getTopTracks](https://www.last.fm/api/show/artist.getTopTracks) is the ranking source. A valid API key is required for a fresh request. Lack of a key or connection leaves the local fallback available.
- This delivery packages **Windows x64 only**. The published Ubuntu 2.7.0 package is unchanged; no Ubuntu release is built or published for 2.8.0.

## Validation

39 unique targeted cases passed across final runs, including Last.fm ranking/cache/offline/failure paths, artist/track/album mix entry points, unchanged radio behavior, 20 featured cards, icon actions, drag/drop, stale response handling and existing album drag layouts. A drag-test gesture was corrected to finish beyond the last row; its seven-case file was rerun successfully. Full static analysis passed. The release manifest records build, native integration and installation results. This is targeted coverage, not a full-suite rerun or live-account certification.
