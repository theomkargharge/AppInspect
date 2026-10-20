#!/usr/bin/env bash
# Records the LinkedIn demo on an iOS simulator and exports it as a 1080x1920
# MP4, ready to post.
#
#   tool/record_linkedin_demo.sh                  # iPhone 17 Pro
#   tool/record_linkedin_demo.sh "iPhone 16 Pro"  # another simulator
#
# To just watch it: flutter run -t tool/linkedin_demo.dart
#
# Needs Xcode and network access: the demo app calls dummyjson.com.
set -euo pipefail

DEVICE="${1:-iPhone 17 Pro}"
cd "$(dirname "$0")/.."
OUT="demo_output"
mkdir -p "$OUT"
LOG="$OUT/test.log"
RAW="$OUT/raw.mov"
FINAL="$OUT/app_inspect_linkedin_1080x1920.mp4"

UDID=$(xcrun simctl list devices available | grep -m1 "    $DEVICE (" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}')
if [ -z "$UDID" ]; then
  echo "No simulator named \"$DEVICE\". See: xcrun simctl list devices available" >&2
  exit 1
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
# A clean status bar, as in Apple's own screenshots.
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3

echo "Building and starting the demo on $DEVICE..."
: > "$LOG"
# Debug build: the only kind a simulator runs.
flutter run -t tool/linkedin_demo.dart -d "$UDID" < /dev/null > "$LOG" 2>&1 &
TEST_PID=$!

# The story starts on DEMO_START: record from there.
until grep -q "DEMO_START" "$LOG"; do
  if ! kill -0 "$TEST_PID" 2>/dev/null || grep -q "DEMO_FAILED" "$LOG"; then
    echo "The demo stopped before it started. See $LOG" >&2
    exit 1
  fi
  sleep 0.1
done
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$RAW" 2>"$OUT/record.log" &
REC_PID=$!
echo "Recording..."

until grep -qE "DEMO_END|DEMO_FAILED" "$LOG"; do
  if ! kill -0 "$TEST_PID" 2>/dev/null; then break; fi
  sleep 0.1
done
kill -INT "$REC_PID"
wait "$REC_PID" || true
# Stop flutter run and the app.
pkill -f "flutter_tools.snapshot run -t tool/linkedin_demo.dart" || true
wait "$TEST_PID" 2>/dev/null || true

if grep -q "DEMO_FAILED" "$LOG"; then
  echo "The demo failed partway. See $LOG" >&2
  exit 1
fi

echo "Exporting 1080x1920..."
swift tool/export_vertical.swift "$RAW" "$FINAL"
echo "Done: $(pwd)/$FINAL"
