#!/bin/zsh
# Build mynote for the simulator, install it and launch it.
# Usage: scripts/sim.sh [simulator-udid]
set -e
cd "$(dirname "$0")/.."
UDID=${1:-99D834DE-30F1-4F3D-9866-72EC219C9DC6}
xcodegen generate --quiet
xcodebuild -project mynote.xcodeproj -scheme mynote -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath build/DerivedData build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/mynote.app
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" com.andi.mynote >/dev/null
echo "launched"
