# Music Time 2.6.1

Fixes a Windows process crash while restoring playback. Crash dumps identified a null renderer string in the bundled OpenAL audio output. Windows now uses WASAPI explicitly for both normal playback and crossfade players, without falling back to OpenAL. An unavailable output produces a playback error and can be retried after reconnecting the device.

Regression coverage: paused restoration of 24-bit PCM, an unavailable WASAPI device, successful recovery, and all three overlap modes. Native Windows integration and installation checks are recorded separately in the release manifest.

Includes the 2.6.0 library-to-queue drag and drop, Last.fm genre/mood playlist templates, and autoplay modes in the existing Play contínuo control. Icon packages are unchanged.

Smart fades analysis currently covers local 16-bit PCM WAV; other formats use the configured fixed fade. Mix only requires supported local analysis and the equalizer disabled. Sequential album playback bypasses fades.

Ubuntu final packages use the same source. Real Linux audio, tray behavior and cloud acceptance remain for validation in a VM or separate partition. The package identifier music-time-preview is retained for upgrades and profile continuity.
