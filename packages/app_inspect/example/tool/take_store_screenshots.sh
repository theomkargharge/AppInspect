#!/usr/bin/env bash
# Takes the pub.dev screenshots on an iOS simulator and saves them as WebP in
# packages/app_inspect/screenshots. Needs Python with Pillow for the WebP files.
#
#   tool/take_store_screenshots.sh                  # iPhone 17 Pro
#   tool/take_store_screenshots.sh "iPhone 16 Pro"  # another simulator
set -euo pipefail

DEVICE="${1:-iPhone 17 Pro}"
cd "$(dirname "$0")/.."
OUT="demo_output/screenshots"
mkdir -p "$OUT"
LOG="$OUT/run.log"

UDID=$(xcrun simctl list devices available | grep -m1 "    $DEVICE (" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}')
if [ -z "$UDID" ]; then
  echo "No simulator named \"$DEVICE\"." >&2
  exit 1
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3

: > "$LOG"
flutter run -t tool/store_screenshots.dart -d "$UDID" < /dev/null > "$LOG" 2>&1 &
RUN_PID=$!

taken=""
until grep -qE "SHOTS_DONE|SHOTS_FAILED" "$LOG"; do
  if ! kill -0 "$RUN_PID" 2>/dev/null; then break; fi
  for name in $(grep -oE "SHOT:[a-z_]+" "$LOG" | cut -d: -f2); do
    case " $taken " in *" $name "*) continue ;; esac
    xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
    taken="$taken $name"
    echo "Took $name"
  done
  sleep 0.2
done
pkill -f "flutter_tools.snapshot run -t tool/store_screenshots.dart" || true
wait "$RUN_PID" 2>/dev/null || true
if grep -q "SHOTS_FAILED" "$LOG"; then
  echo "Stopped partway. See $LOG" >&2
  exit 1
fi

# The size pub.dev's screenshots already use.
python3 - "$OUT" ../screenshots <<'EOF'
import sys, glob, os
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
for path in sorted(glob.glob(os.path.join(src, '*.png'))):
    image = Image.open(path).convert('RGB')
    image = image.resize((600, round(600 * image.height / image.width)), Image.LANCZOS)
    name = os.path.splitext(os.path.basename(path))[0]
    image.save(os.path.join(dst, name + '.webp'), 'WEBP', quality=88, method=6)
    print('Saved', name + '.webp', image.size)
EOF
