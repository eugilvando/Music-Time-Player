#!/bin/sh
# VM-safe default, with explicit alternatives for driver diagnostics.
case "${MUSIC_TIME_RENDERER:-compatibility}" in
  compatibility)
    export FLUTTER_LINUX_RENDERER=opengl
    export LIBGL_ALWAYS_SOFTWARE=1
    export GDK_BACKEND="${GDK_BACKEND:-x11}"
    ;;
  software)
    export FLUTTER_LINUX_RENDERER=software
    export LIBGL_ALWAYS_SOFTWARE=1
    export GDK_BACKEND="${GDK_BACKEND:-x11}"
    ;;
  hardware)
    export FLUTTER_LINUX_RENDERER=opengl
    export LIBGL_ALWAYS_SOFTWARE=0
    ;;
  *)
    printf '%s\n' 'Invalid MUSIC_TIME_RENDERER. Use compatibility, software or hardware.' >&2
    exit 2
    ;;
esac
exec /opt/music-time-preview/music_time "$@"
