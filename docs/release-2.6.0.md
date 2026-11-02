# Music Time 2.6.0+58

Drag tracks or a selection from library lists, detailed rows and compact cards onto the queue button to append them. Drop on an existing queue row to insert before it, or into the empty queue. The current occurrence and shuffle restoration order are preserved. Queue changes are saved.

The existing Continuous play control opens a mode menu. Settings → Playback offers the same preference and batch size. Same genre retains the previous behavior. Shuffle Specialist varies the library with recent tracks deprioritized. Double Shot groups available tracks by artist, with single tracks allowed when a partner is missing. Artist Fan uses the artists at the end of the queue. Era Enthusiast stays within the current track's decade and stops when dates or candidates are missing. Manually queued tracks play before generated suggestions. Hidden and unavailable tracks are excluded.

Insights → Create playlist now offers genre and mood templates. Genre combines Last.fm tag rankings with matching local genre metadata. Mood uses community tags for calm, melancholic, energetic and happy. Only unambiguous matches in the eligible library are included. Preview, save and play use the existing playlist flow. Seven-day tag caches support offline use. Rankings currently inspect up to 200 Last.fm candidates per tag. Actual account acceptance remains separate from controlled HTTP tests.

Settings → Playback adds Crossfade, Smart fades and Mix only, with a maximum overlap from 1–12 seconds and disabled by default. Sequential transitions within an album are preserved. Crossfade prepares the next source through the existing resolver and overlaps two players with volume ramps. Unready sources use the ordinary end-of-track advance.

Smart fades currently analyzes bounded peak envelopes of local 16-bit PCM WAV files. Other formats use the configured crossfade duration. Mix only uses an analyzed overlap without volume ramps, and requires supported local WAV analysis and a disabled equalizer. It skips overlap when analysis finds insufficient headroom. This is not beat matching or loudness normalization. Real cloud buffering, speaker output and Ubuntu desktop audio still require device acceptance.

Pause, seek, changing tracks and clearing the queue cancel the outgoing tail. Listening sessions retain separate timing and existing duplicate prevention. Icon packs were excluded from this update.

Windows validation passed. 35 unique targeted cases passed across runs, including six final feature tests. Analysis, release build and native SMTC/tray checks passed. The first regression run exposed a next-track duration readiness issue, corrected and retested. No full-suite claim. See the release manifest for scope and installer checksum.
