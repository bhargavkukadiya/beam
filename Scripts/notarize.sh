#!/bin/bash
set -euo pipefail

# Navigate to project root directory
cd "$(dirname "$0")/.."

APP_NAME="Beam"
APP_BUNDLE="$APP_NAME.app"

# Ensure app bundle exists, or trigger build
if [ ! -d "$APP_BUNDLE" ]; then
    echo "⚠️  $APP_BUNDLE not found. Building release bundle first..."
    ./Scripts/build-app.sh
fi

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")}"
VERSION="${VERSION#v}"
VERSION="${VERSION#V}"
DIST_ZIP="${APP_NAME// /-}-${VERSION}.zip"

echo "📦 Packaging $APP_BUNDLE into $DIST_ZIP..."
ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_ZIP"

echo "🚀 Submitting $DIST_ZIP to Apple Notary Service..."
if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
    xcrun notarytool submit "$DIST_ZIP" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
elif [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
    xcrun notarytool submit "$DIST_ZIP" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" --wait
else
    echo "❌ Missing notarization credentials."
    echo "Please set NOTARY_KEYCHAIN_PROFILE or NOTARY_APPLE_ID, NOTARY_TEAM_ID, and NOTARY_PASSWORD."
    exit 1
fi

echo "📎 Stapling notarization ticket to $APP_BUNDLE..."
xcrun stapler staple "$APP_BUNDLE"

echo "🔍 Validating stapled ticket..."
xcrun stapler validate "$APP_BUNDLE"

echo "🛡️ Assessing Gatekeeper execution status..."
spctl -a -vvv --type execute "$APP_BUNDLE"

echo "📦 Re-packaging stapled distribution archive..."
rm -f "$DIST_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_ZIP"

echo "🔒 Generating SHA-256 checksum..."
shasum -a 256 "$DIST_ZIP" > "$DIST_ZIP.sha256"
echo "   SHA-256: $(cat "$DIST_ZIP.sha256")"

echo "✅ Notarization complete: $DIST_ZIP"
