# Music Time 2.7.0

## What's new

- Drag an album from the library, artist discography or Home to the queue. Tracks follow disc and track order.
- Crossfade settings now separate Off, Automatic and Manual modes. Automatic chooses up to six seconds based on track lengths, with compatible local waveform analysis when available. Manual mode retains Smooth, Smart fades and Mix only.
- Playback settings have clearer labels and more space between controls. The existing Continuous play button is aligned with the other playback controls.
- Insights offers 19 mood templates using Last.fm tags and matching tracks in your library.
- Import AutoEQ `ParametricEQ.txt` files, review their filters and save named profiles. Peak, low-shelf and high-shelf filters are applied with protective preamp adjustment. The existing five-band presets remain available.
- Assign an EQ profile to each system output device. When the default output changes, Music Time applies that device's saved profile. Outputs without an assignment use no EQ. Available for Windows and Ubuntu with PulseAudio/PipeWire's PulseAudio interface.

## Using output profiles

Open **Settings → Playback and audio → Equalizer**. Import an AutoEQ text profile or select an existing preset. Enable **Profile per output device**, select the output in your operating system, then choose its profile in Music Time. Repeat for your headphones, speakers or other outputs. Detection can take about two seconds.

## Scope and compatibility

AutoEQ integration imports files; it does not search or download headphone profiles from autoeq.app. Imported source files are not modified. Sequential album playback keeps its original transitions. Waveform analysis currently supports local PCM16 WAV files; Automatic and Smart fades use duration-based transitions for other formats. Mix only requires compatible analysis and EQ disabled.

Windows retains the WASAPI-only crash fix introduced in 2.6.1 and uses a pinned LGPL libmpv build that includes the required parametric filters. The native archive and checksums accompany this release. See the native provenance manifest and third-party notices in the repository.

Ubuntu keeps the `music-time-preview` package identifier for upgrades and profile continuity. Real audio, output switching and desktop tray behavior still need acceptance in the user's VM or separate partition.

Validation results are recorded in the release manifest.
