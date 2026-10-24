#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ubuntu-smoke
export LIBGL_ALWAYS_SOFTWARE=1
binary="${MUSIC_TIME_SMOKE_BINARY:-build/linux/x64/release/bundle/music_time}"
mode="${MUSIC_TIME_RENDERER:-compatibility}"
"$binary" --migrate-library-only > "build/ubuntu-smoke/migration-$mode.log" 2>&1
"$binary" --design-preview > "build/ubuntu-smoke/preview-$mode.log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true' EXIT
sleep 15
kill -0 "$pid"
window="$(xdotool search --name 'Music Time' | head -n 1)"
test -n "$window"
import -window "$window" "build/ubuntu-smoke/home-$mode.png"
xdotool mousemove --window "$window" 75 620 click 1
sleep 3
import -window "$window" "build/ubuntu-smoke/settings-$mode.png"
xdotool windowsize "$window" 1000 700
sleep 3
import -window "$window" "build/ubuntu-smoke/resized-$mode.png"
grep -q 'impeller=disabled' "build/ubuntu-smoke/preview-$mode.log"
if test "$binary" = /usr/bin/music-time-preview; then
  if test "$mode" = software; then
    grep -q 'renderer=software; impeller=disabled' "build/ubuntu-smoke/preview-$mode.log"
  else
    grep -q 'renderer=opengl; impeller=disabled; software_gl=1' "build/ubuntu-smoke/preview-$mode.log"
  fi
fi
if grep -E 'Unhandled exception|Error while loading shared libraries|Failed to load dynamic library|Failed to start' build/ubuntu-smoke/*.log; then exit 1; fi
echo 'Linux migration and graphical launch completed; real playback and cloud acceptance remain pending.'
