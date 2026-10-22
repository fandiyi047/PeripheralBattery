#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/PeripheralBattery.app"
MODE="${1:-run}"
if [[ "$MODE" != "--build" ]]; then pkill -x PeripheralBattery 2>/dev/null || true; fi
mkdir -p "$APP/Contents/MacOS"
clang -Os -fobjc-arc -mmacosx-version-min=13.0 "$ROOT/src/main.m" -framework AppKit -framework IOKit -o "$APP/Contents/MacOS/PeripheralBattery"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PeripheralBattery</string>
<key>CFBundleIdentifier</key><string>local.fy.PeripheralBattery</string>
<key>CFBundleName</key><string>外设电量</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>9</string>
<key>CFBundleShortVersionString</key><string>1.3.1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/bin/python3 "$ROOT/script/sign.py" "$APP"
case "$MODE" in
 --build) ;;
 --once|--self-test) "$APP/Contents/MacOS/PeripheralBattery" "$MODE" ;;
 --verify) open "$APP"; sleep 2; pgrep -x PeripheralBattery ;;
 run) open "$APP" ;;
 *) echo 'Usage: build_and_run.sh [--build|--once|--self-test|--verify]' >&2; exit 2 ;;
esac
