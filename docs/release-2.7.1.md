# Music Time 2.7.1

Fixes missing album artwork in Windows media controls after crossfade transitions. Incoming queue entries now load their catalog artwork before becoming the active track, matching manual next/previous playback. Optional artwork failures do not interrupt audio.

Validation: the missing-cover regression failed on the previous code and passed after the fix. Five targeted tests passed, including four native overlap modes and manual previous/next artwork checks. Static analysis, Windows release build and native media/tray integration passed. This is targeted regression coverage, not a new full-suite run. Listening quality and acceptance with the user's current album remain separate.

Ubuntu 2.7.0 remains the published final Linux package.