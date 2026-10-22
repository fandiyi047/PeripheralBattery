#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/Applications/PeripheralBattery.app"
PLIST="$HOME/Library/LaunchAgents/local.fy.PeripheralBattery.plist"
DOMAIN="gui/$(id -u)"
launchctl bootout "$DOMAIN/local.fy.PeripheralBattery" 2>/dev/null || true
pkill -x PeripheralBattery 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
ditto "$ROOT/PeripheralBattery.app" "$DEST"
/usr/bin/python3 - "$PLIST" "$DEST" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
 plistlib.dump({'Label':'local.fy.PeripheralBattery','ProgramArguments':['/usr/bin/open','-g',sys.argv[2]],'RunAtLoad':True,'LimitLoadToSessionType':'Aqua','ProcessType':'Background'},f)
PY
chmod 644 "$PLIST"
plutil -lint "$PLIST"
launchctl enable "$DOMAIN/local.fy.PeripheralBattery"
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Installed: $DEST"
