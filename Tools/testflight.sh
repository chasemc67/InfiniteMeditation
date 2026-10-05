#!/usr/bin/env bash
# Archive the iOS app (with the embedded watchOS app) and upload it to App Store Connect / TestFlight.
#
# Required environment:
#   ASC_KEY_ID      App Store Connect API key ID (e.g. ABC123DEFG)
#   ASC_ISSUER_ID   Issuer ID shown above the keys list in App Store Connect
#   ASC_KEY_PATH    Path to the downloaded AuthKey_<KEY_ID>.p8 (default: ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8)
# Optional:
#   BUILD_NUMBER    Defaults to a UTC timestamp so every upload is unique.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?Set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
ARCHIVE_PATH="build/InfiniteMeditation-${BUILD_NUMBER}.xcarchive"

AUTH=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

echo "==> Archiving build $BUILD_NUMBER"
xcodebuild \
  -project HapticMeditation.xcodeproj \
  -scheme HapticMeditation \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  "${AUTH[@]}" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

echo "==> Exporting and uploading to App Store Connect"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist Config/ExportOptions.plist \
  -exportPath build/export \
  "${AUTH[@]}"

echo "==> Uploaded build $BUILD_NUMBER. It appears in App Store Connect › TestFlight after processing (usually 5–30 min)."
