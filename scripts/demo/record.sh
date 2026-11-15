#!/bin/bash
# Records the website animation from the scripted demo (DemoStory) and converts it to MP4, WebM and GIF.
#
#   scripts/demo/record.sh [scene]      record and convert; scene = approval (default) | pill | music
#   scripts/demo/record.sh --calibrate  save screenshots at the moments the pointer needs to hit (approval)
#
# Scenes: approval = the full request/approve story (triage-demo.*); pill = the collapsed pill alone
# (triage-pill.*); music = a Live Activity opens and the pill slides aside (triage-music.*).
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
CALIBRATE=0; SCENE="${1:-approval}"
[ "$SCENE" = "--calibrate" ] && { CALIBRATE=1; SCENE=approval; }
case "$SCENE" in
  approval) REGION_H=470; REC_SECONDS=19; DUR=12.9; NAME=triage-demo;  POSTER_T=9.6 ;;   # DUR ends on the collapsed pill
  pill)     REGION_H=110; REC_SECONDS=16; DUR=9.8;  NAME=triage-pill;  POSTER_T=5.6 ;;
  music)    REGION_H=110; REC_SECONDS=14; DUR=7.8;  NAME=triage-music; POSTER_T=4.2 ;;
  *) echo "unknown scene: $SCENE (approval | pill | music)" >&2; exit 1 ;;
esac
REGION_W=720; REGION_X=$((CX - REGION_W / 2))
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
open -n "$ROOT/build/Triage.app" --args --demo-story --demo-wait "--demo-scene=$SCENE"
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

if [ "$SCENE" = "approval" ]; then
  /tmp/triage-demo-cursor "$APPROVE_X" "$APPROVE_Y" "$PILL_X" "$PILL_Y" "$REST_X" "$REST_Y" > /tmp/triage-demo-cursor.log 2>&1 &
  CURSOR_PID=$!
else
  /tmp/triage-demo-cursor park "$REST_X" "$REST_Y"; CURSOR_PID=""        # strips show no pointer
fi
screencapture -v -V "$REC_SECONDS" -R "$REGION_X,0,$REGION_W,$REGION_H" /tmp/triage-demo.mov &
REC_PID=$!
sleep 2.5
touch /tmp/triage-demo-go                                    # the story starts now
wait $REC_PID || true
[ -n "$CURSOR_PID" ] && { wait $CURSOR_PID 2>/dev/null || true; }
pkill -x Triage 2>/dev/null || true

# --- convert -----------------------------------------------------------------------------------
# Find the sync marker (a white square the stage flashes just before the story starts) in the recording:
# average the marker's pixels for every frame (the video is 2x, so the marker is 24x24 at (16,180)).
M_OFF=$(ffmpeg -v error -i /tmp/triage-demo.mov -vf "fps=30,crop=24:24:16:180,format=gray" -f rawvideo -pix_fmt gray - 2>/dev/null | python3 -c "
import sys
data = sys.stdin.buffer.read(); n = 24 * 24
bright = [i / 30 for i in range(len(data) // n) if sum(data[i * n:(i + 1) * n]) / n > 150]
if len(bright) < 4: sys.exit(1)
print(bright[-1] + 1 / 30)
") || { echo "ERROR: did not find the sync marker in the recording (the recording started too late?). Nothing kept." >&2; exit 1; }
# The story starts 1.2s after the marker disappears; start the clip 0.25s after it, so it opens on 0.95s of idle stage.
SS=$(python3 -c "print($M_OFF + 0.25)")
cd "$OUT"
ffmpeg -v error -y -i /tmp/triage-demo.mov -ss "$SS" -t "$DUR" \
  -vf "fps=30,scale=1440:-2" -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart -an $NAME.mp4
ffmpeg -v error -y -i /tmp/triage-demo.mov -ss "$SS" -t "$DUR" \
  -vf "fps=30,scale=1440:-2" -c:v libvpx-vp9 -crf 32 -b:v 0 -pix_fmt yuv420p -row-mt 1 -an $NAME.webm
ffmpeg -v error -y -i /tmp/triage-demo.mov -ss "$SS" -t "$DUR" \
  -vf "fps=15,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" -loop 0 $NAME.gif
# Safety: the stage disappears when the demo quits, which would show the real desktop and menu bar.
# The story keeps the stage up well past the end of every clip, so a clip of exactly the intended length
# can never contain it. If a length is off, refuse to keep anything.
for f in "$NAME.mp4" "$NAME.webm"; do
  LEN=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  python3 -c "import sys; sys.exit(0 if abs($LEN - $DUR) < 0.15 else 1)" || { echo "ERROR: $f is ${LEN}s, expected ${DUR}s; refusing to keep it (it may show the real desktop)" >&2; rm -f "$NAME".{mp4,webm,gif} "$NAME-poster.png"; exit 1; }
done
ffmpeg -v error -y -ss "$(python3 -c "print($SS + $POSTER_T)")" -i /tmp/triage-demo.mov -frames:v 1 -vf "scale=1440:-2" $NAME-poster.png
ls -la "$OUT" | awk '{print $5, $9}' | tail -n +4
