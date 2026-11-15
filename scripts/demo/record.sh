#!/bin/bash
# Records the website animation from the scripted demo (DemoStory) and converts it to MP4, WebM and GIF.
#
#   scripts/demo/record.sh              record and convert
#   scripts/demo/record.sh --calibrate  just save screenshots at the moments the pointer needs to hit
#
# Hands off the mouse while it runs (about 25 seconds). Your real triage and any music are restored.
# Environment: OUT (default ~/Desktop/triage-demo), CX (screen center x in points, default 868),
#              APPROVE_X / APPROVE_Y (where the Approve button is, in points).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${OUT:-$HOME/Desktop/triage-demo}"
CX="${CX:-868}"
APPROVE_X="${APPROVE_X:-698}"; APPROVE_Y="${APPROVE_Y:-212}"
PILL_X=$((CX - 85)); PILL_Y=25
REST_X=$((CX + 440)); REST_Y=260
REGION_W=720; REGION_H=470; REGION_X=$((CX - REGION_W / 2))
CALIBRATE=0; [ "${1:-}" = "--calibrate" ] && CALIBRATE=1
mkdir -p "$OUT"

command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)" >&2; exit 1; }

# --- remember and quiet the machine ---------------------------------------------------------
REAL_WAS_RUNNING=0; pgrep -x Triage >/dev/null && REAL_WAS_RUNNING=1
MUSIC_WAS_PLAYING=0
if pgrep -x Music >/dev/null && [ "$(osascript -e 'tell application "Music" to get player state' 2>/dev/null)" = "playing" ]; then MUSIC_WAS_PLAYING=1; fi
restore() {
  pkill -x Triage 2>/dev/null || true
  [ "$REAL_WAS_RUNNING" = 1 ] && open -a /Applications/Triage.app 2>/dev/null || true
  [ "$MUSIC_WAS_PLAYING" = 1 ] && osascript -e 'tell application "Music" to play' 2>/dev/null || true
}
trap restore EXIT

swiftc -O -o /tmp/triage-demo-cursor "$ROOT/scripts/demo/demo-cursor.swift"
[ "$MUSIC_WAS_PLAYING" = 1 ] && osascript -e 'tell application "Music" to pause' && sleep 1.5

pkill -x Triage 2>/dev/null || true; sleep 1
rm -f /tmp/triage-demo-go /tmp/triage-demo-t0 /tmp/triage-demo.mov
open -n "$ROOT/build/Triage.app" --args --demo-story --demo-wait
sleep 2.5                                                    # stage window up, menu bar hidden

if [ "$CALIBRATE" = 1 ]; then
  touch /tmp/triage-demo-go
  while [ ! -f /tmp/triage-demo-t0 ]; do sleep 0.05; done
  T0=$(cat /tmp/triage-demo-t0)
  for T in 3.0 6.4 11.0; do
    sleep "$(python3 -c "import time; print(max(0, $T - (time.time() - $T0)))")"
    screencapture -x -R "$REGION_X,0,$REGION_W,$REGION_H" "$OUT/calibrate_$T.png"
  done
  echo "saved calibration frames in $OUT"
  exit 0
fi

/tmp/triage-demo-cursor "$APPROVE_X" "$APPROVE_Y" "$PILL_X" "$PILL_Y" "$REST_X" "$REST_Y" > /tmp/triage-demo-cursor.log 2>&1 &
CURSOR_PID=$!
E_START=$(python3 -c "import time; print(time.time())")
screencapture -v -V 17 -R "$REGION_X,0,$REGION_W,$REGION_H" /tmp/triage-demo.mov &
REC_PID=$!
sleep 2.0
touch /tmp/triage-demo-go                                    # the story starts now
wait $REC_PID || true
wait $CURSOR_PID 2>/dev/null || true
pkill -x Triage 2>/dev/null || true

# --- convert -----------------------------------------------------------------------------------
E_T0=$(cat /tmp/triage-demo-t0)
SS=$(python3 -c "print(max(0, $E_T0 - $E_START - 0.9))")      # a little idle before the story starts
DUR=12.9                                                    # ends on the collapsed pill, so the loop is clean
cd "$OUT"
ffmpeg -v error -y -ss "$SS" -t "$DUR" -i /tmp/triage-demo.mov \
  -vf "fps=30,scale=1440:-2" -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart -an triage-demo.mp4
ffmpeg -v error -y -ss "$SS" -t "$DUR" -i /tmp/triage-demo.mov \
  -vf "fps=30,scale=1440:-2" -c:v libvpx-vp9 -crf 32 -b:v 0 -pix_fmt yuv420p -row-mt 1 -an triage-demo.webm
ffmpeg -v error -y -ss "$SS" -t "$DUR" -i /tmp/triage-demo.mov \
  -vf "fps=15,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" -loop 0 triage-demo.gif
ffmpeg -v error -y -ss "$(python3 -c "print($SS + 9.6)")" -i /tmp/triage-demo.mov -frames:v 1 -vf "scale=1440:-2" poster.png
ls -la "$OUT" | awk '{print $5, $9}' | tail -n +4
