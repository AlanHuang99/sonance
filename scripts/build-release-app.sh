#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-0.1.0-dev}"
BUILD_NUMBER="${2:-1}"
# Scheme selects the distribution channel: "Sonance" is the Sparkle-free base /
# App Store build; "Sonance-Direct" links Sparkle for the GitHub Releases build.
# Both produce Sonance.app at the same path (shared PRODUCT_NAME).
SCHEME="${3:-Sonance}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build}"

xcodegen generate

xcodebuild \
  -project Sonance.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS="arm64 x86_64" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$ROOT/$DERIVED_DATA_PATH/Build/Products/Release/Sonance.app"
test -d "$APP"
plutil -lint "$APP/Contents/Info.plist"
echo "$APP"
