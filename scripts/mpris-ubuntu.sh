#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ubuntu-smoke
fixture="$(mktemp -d)"
binary="${MUSIC_TIME_SMOKE_BINARY:-build/linux/x64/release/bundle/music_time}"
python3 - "$fixture/demo.wav" <<'PY'
import wave,sys
with wave.open(sys.argv[1], 'wb') as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(44100)
    f.writeframes(b'\x00\x00' * 44100 * 120)
PY
export XDG_CONFIG_HOME="$fixture/config" XDG_DATA_HOME="$fixture/data" LIBGL_ALWAYS_SOFTWARE=1
"$binary" --validation-profile "--smoke-audio=$fixture/demo.wav" >build/ubuntu-smoke/mpris.log 2>&1 &
app_pid=$!
trap 'kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true; rm -rf -- "$fixture"' EXIT
service="org.mpris.MediaPlayer2.MusicTime.instance$app_pid"
call() { gdbus call --session --dest "$service" --object-path /org/mpris/MediaPlayer2 --method "$@"; }
for attempt in $(seq 1 45); do
  if call org.freedesktop.DBus.Properties.Get org.mpris.MediaPlayer2.Player Metadata >build/ubuntu-smoke/mpris-metadata.txt 2>/dev/null && grep -q xesam:title build/ubuntu-smoke/mpris-metadata.txt; then break; fi
  kill -0 "$app_pid"
  sleep 1
done
grep -q xesam:title build/ubuntu-smoke/mpris-metadata.txt
call org.mpris.MediaPlayer2.Player.Pause
sleep 1
call org.freedesktop.DBus.Properties.Get org.mpris.MediaPlayer2.Player PlaybackStatus | grep -q Paused
call org.mpris.MediaPlayer2.Player.Play
sleep 1
call org.freedesktop.DBus.Properties.Get org.mpris.MediaPlayer2.Player PlaybackStatus | grep -q Playing
window="$(xdotool search --pid "$app_pid" --name 'Music Time' | head -n 1)"
test -n "$window"
xdotool windowunmap "$window"
call org.mpris.MediaPlayer2.Player.Pause
sleep 1
call org.freedesktop.DBus.Properties.Get org.mpris.MediaPlayer2.Player PlaybackStatus | grep -q Paused
call org.mpris.MediaPlayer2.Raise
call org.mpris.MediaPlayer2.Quit
for attempt in $(seq 1 15); do
  if ! kill -0 "$app_pid" 2>/dev/null; then echo 'MPRIS native playback, hidden window and exit passed'; exit 0; fi
  sleep 1
done
exit 1
