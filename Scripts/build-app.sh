#!/bin/bash
set -euo pipefail

# Navigate to project root directory
cd "$(dirname "$0")/.."

# Product & Identity Configuration
BUNDLE_ID="${BUNDLE_ID:-"com.beam.mac"}"

# Version derivation and strict Apple semver validation (three period-separated integers)
RAW_VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo "1.0.1")}"
CLEAN_VERSION="${RAW_VERSION#v}"
CLEAN_VERSION="${CLEAN_VERSION#V}"

if [[ "$CLEAN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    VERSION="$CLEAN_VERSION"
elif [[ "$CLEAN_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
    VERSION="${CLEAN_VERSION}.0"
elif [[ "$CLEAN_VERSION" =~ ^[0-9]+$ ]]; then
    VERSION="${CLEAN_VERSION}.0.0"
else
    VERSION="1.0.1"
fi

BUILD_NUMBER="${BUILD_NUMBER:-"1"}"
CURRENT_YEAR="$(date +%Y)"
COPYRIGHT="${COPYRIGHT:-"Copyright © ${CURRENT_YEAR} Bhargav Kukadiya. All rights reserved."}"

# Build architectures (Universal by default)
ARCHS="${ARCHS:---arch arm64 --arch x86_64}"
echo "🔨 Building Beam ($ARCHS)..."
swift build -c release $ARCHS

APP_NAME="Beam"
APP_BUNDLE="$APP_NAME.app"

# Locate compiled binary dynamically matching the exact build configuration
BIN_DIR="$(swift build -c release $ARCHS --show-bin-path)"
BINARY_PATH="$BIN_DIR/BeamApp"

if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Could not find compiled binary at $BINARY_PATH"
    exit 1
fi

# Remove old bundle
rm -rf "$APP_BUNDLE"

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/BeamApp"

# Copy AppIcon from Resources
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Instantiate Info.plist from Config/Info.plist using plist-aware mutation (escapes &, <, > safely)
cp "Config/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "${BUNDLE_ID}" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "${VERSION}" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${BUILD_NUMBER}" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace NSHumanReadableCopyright -string "${COPYRIGHT}" "$APP_BUNDLE/Contents/Info.plist"
plutil -lint "$APP_BUNDLE/Contents/Info.plist"

# Copy entitlements from Config/Beam.entitlements
cp "Config/Beam.entitlements" "$APP_BUNDLE/Contents/entitlements.plist"

# Codesign the app with Hardened Runtime
SIGNING_IDENTITY="${SIGNING_IDENTITY:-"-"}"
CODESIGN_FLAGS="--options runtime"
if [ "$SIGNING_IDENTITY" != "-" ]; then
    CODESIGN_FLAGS="$CODESIGN_FLAGS --timestamp"
fi

echo "🔏 Signing app bundle (Identity: $SIGNING_IDENTITY)..."
codesign --force --deep --sign "$SIGNING_IDENTITY" $CODESIGN_FLAGS --entitlements "$APP_BUNDLE/Contents/entitlements.plist" --identifier "${BUNDLE_ID}" "$APP_BUNDLE"

# Strict verification of signature
echo "🔍 Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "✅ App bundle created and signed: $APP_BUNDLE"

# Distribution Archive & Notarization Workflow
CREATE_DIST_ZIP="${CREATE_DIST_ZIP:-true}"
NOTARIZE="${NOTARIZE:-false}"
DIST_ZIP="${APP_NAME// /-}-${VERSION}.zip"

if [ "$NOTARIZE" = "true" ] || [ "$CREATE_DIST_ZIP" = "true" ]; then
    echo "📦 Creating distribution archive: $DIST_ZIP..."
    ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_ZIP"

    if [ "$NOTARIZE" = "true" ]; then
        if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
            echo "🚀 Submitting $DIST_ZIP to Apple Notary Service (Profile: $NOTARY_KEYCHAIN_PROFILE)..."
            xcrun notarytool submit "$DIST_ZIP" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
        elif [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
            echo "🚀 Submitting $DIST_ZIP to Apple Notary Service..."
            xcrun notarytool submit "$DIST_ZIP" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" --wait
        else
            echo "❌ Notarization requested, but NOTARY_KEYCHAIN_PROFILE or APPLE_ID/TEAM_ID/PASSWORD credentials are missing."
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
    fi

    echo "🔒 Generating SHA-256 checksum..."
    shasum -a 256 "$DIST_ZIP" > "$DIST_ZIP.sha256"
    echo "   SHA-256: $(cat "$DIST_ZIP.sha256")"
fi

if [ "$NOTARIZE" != "true" ] && [ "$SIGNING_IDENTITY" != "-" ]; then
    echo "ℹ️ Development build signed with Developer ID. Gatekeeper acceptance requires notarization (--notarize)."
fi

echo ""
echo "To run the app:"
echo "  open \"$APP_BUNDLE\""
echo ""
echo "To install to Applications:"
echo "  cp -r \"$APP_BUNDLE\" /Applications/"
