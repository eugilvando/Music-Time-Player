# Music Time 2.5.5+57

Favoriting a track in Music Time now also loves it on the connected Last.fm account. Individual and multi-selection actions are supported. Settings → Integrations → Last.fm includes an export toggle and delivery status. Offline/failed deliveries are retained locally and retried. Existing favorites are not automatically exported; unfavoriting locally does not remove a Last.fm love. Authorization is required; scrobbling and the public profile username are independent. Pending deliveries stay bound to the original session and are never redirected to another account.

Ubuntu source now enables close/minimize-to-tray with a PNG icon and checks for an active AppIndicator/StatusNotifier host before hiding. Desktop filename and themed icon now match the existing GTK application ID. Profile identity and graphics compatibility settings are preserved. Linux build and real desktop acceptance remain pending in a separate partition/VM. The available Ubuntu download remains 2.5.4 Preview 1.

Windows validation: 402 unique cases passed across runs. The full run had 400 passes and two test-harness failures (offscreen tap after layout changed; outdated category count excluding About); both corrected and passed in an eight-test UI rerun. 20 overlapping tests repeated on the public snapshot; static analysis and release build passed. Native media/tray integration passed in an isolated profile. Authorized local installation completed with database, preferences and vault preserved; installed binaries match the validated build. Real Last.fm account acceptance remains separate from controlled HTTP tests.

## Ubuntu acceptance

Build the main branch on Ubuntu 24.04, then run `bash scripts/package-ubuntu.sh`. Verify the icon in the dock/Alt+Tab; close and minimize to the tray; restore and use playback/exit menu actions. Confirm normal close/minimize when those options are disabled. With AppIndicator disabled before launching, the window must remain accessible. Unpin and re-pin an old launcher if necessary after the desktop filename changes.
