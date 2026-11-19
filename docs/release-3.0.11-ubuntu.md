# Music Time 3.0.11

This update reduces repeated work when navigating Home, artists, favorites and Insights, and aligns the playback queue toolbar.

- Local artist similarities reuse materialized genre/playlist sets and a covering metadata index. Results are cached across restarts, invalidated when relevant library tables change, and concurrent identical requests share one calculation.
- Local and ListenBrainz Insights repositories now live for the application session, retaining reports, period selection and automatic-refresh guards across navigation. Accounts and services remain isolated; manual refresh is available.
- Home and catalog calculations already in progress are shared across page visits. Completed snapshots are retained even when the originating page has been closed; data/filter keys prevent reuse across incompatible views.
- The playback queue keeps its controls on the left and the track count/options at the right edge, on one line.

Validation uses synthetic libraries and accounts. Database timing measurements are not a guarantee for every library or machine. No personal library, credentials or diagnostics are published. See the platform validation manifest for completed checks.

## Ubuntu

Ubuntu Desktop 24.04 amd64 package: `music-time-preview_3.0.11-0ubuntu1_amd64.deb`. Automated validation covers analysis, regression tests, real D-Bus/MPRIS, graphical startup, package installation and compatibility/software rendering. Physical audio devices and desktop tray extensions still depend on the target environment.
