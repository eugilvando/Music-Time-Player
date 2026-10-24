#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ubuntu-smoke
export LIBGL_ALWAYS_SOFTWARE=1
bundle=build/linux/x64/release/bundle
"$bundle/music_time" --migrate-library-only > build/ubuntu-smoke/migration.log 2>&1
"$bundle/music_time" --design-preview > build/ubuntu-smoke/preview.log 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
sleep 15
kill -0 "$pid"
window="$(xdotool search --name 'Music Time' | head -n 1)"
test -n "$window"
import -window "$window" build/ubuntu-smoke/preview.png
if grep -E 'Unhandled exception|Error while loading shared libraries|Failed to load dynamic library|Failed to start' build/ubuntu-smoke/*.log; then exit 1; fi
echo 'Linux migration and graphical launch completed; real playback and cloud acceptance remain pending.'
