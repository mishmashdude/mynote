#!/bin/zsh
# Archive mynote and upload it to App Store Connect.
# Needs an Apple account signed in to Xcode (Settings → Accounts) for team Z79V56DCGG.
# Usage: scripts/release.sh [build-number]
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=${1:-$(date +%Y%m%d%H%M)}
xcodegen generate --quiet
ARCHIVE=build/mynote-$BUILD.xcarchive
xcodebuild archive \
  -project mynote.xcodeproj -scheme mynote -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" 2>&1 | grep -E "error:|warning: .*[Pp]rovision|ARCHIVE (SUCCEEDED|FAILED)" || true
test -d "$ARCHIVE" || { echo "archive failed"; exit 1; }
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath build/export-$BUILD -allowProvisioningUpdates
echo "Uploaded build $BUILD"
