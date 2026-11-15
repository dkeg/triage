#!/bin/bash
# Makes the 1200x630 social preview image from the approval clip.
#
#   scripts/demo/social.sh [approval.mp4] [out.png]
#
# Pulls a frame where the approval card is open (before the pointer arrives), crops it to the card,
# and composes it with the icon and tagline (scripts/demo/make-social.swift).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IN="${1:-$ROOT/docs/media/triage-demo.mp4}"
OUT="${2:-$ROOT/docs/media/social.png}"
T="${CARD_AT:-4.8}"                         # seconds into the approval clip

ffmpeg -v error -y -ss "$T" -i "$IN" -frames:v 1 /tmp/triage-card-full.png
CROP=$(python3 - <<'PY'
import subprocess
W, H = 1440, 940
raw = subprocess.run(["ffmpeg", "-v", "error", "-i", "/tmp/triage-card-full.png", "-f", "rawvideo", "-pix_fmt", "gray", "-"],
                     capture_output=True).stdout
xs, ys = [], []
for y in range(H):
    row = raw[y * W:(y + 1) * W]
    for x in range(W):
        if row[x] <= 3: xs.append(x); ys.append(y)         # the card is pure black; the stage is lighter
x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
m = 5
print(f"crop={min(x1 - x0 + 1 + 2 * m, W)}:{min(y1 - y0 + 1 + 2 * m, H)}:{max(x0 - m, 0)}:{max(y0 - m, 0)}")
PY
)
ffmpeg -v error -y -i /tmp/triage-card-full.png -vf "$CROP" /tmp/triage-card.png
swiftc -o /tmp/triage-make-social "$ROOT/scripts/demo/make-social.swift"
/tmp/triage-make-social /tmp/triage-card.png "$ROOT/packaging/AppIcon.icns" /tmp/triage-social-2x.png
sips -z 630 1200 /tmp/triage-social-2x.png --out "$OUT" >/dev/null
echo "wrote $OUT"
