#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 /path/to/Sonance.app 'Developer ID Application: ...' [keychain] [entitlements]" >&2
  exit 1
fi

APP_PATH="$1"
IDENTITY="$2"
KEYCHAIN_ARG=()
if [[ $# -ge 3 && -n "${3:-}" ]]; then
  KEYCHAIN_ARG=(--keychain "$3")
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Entitlements default to the base (App Store) target; the Direct build passes
# Sonance/Sonance-Direct.entitlements so its sandboxed Sparkle installer keeps its
# mach-lookup exceptions. Re-signing here is the authoritative signing step (CI
# builds with CODE_SIGNING_ALLOWED=NO), so the file chosen here is what ships.
ENTITLEMENTS_ARG="${4:-Sonance/Sonance.entitlements}"
case "$ENTITLEMENTS_ARG" in
  /*) ENTITLEMENTS="$ENTITLEMENTS_ARG" ;;
  *)  ENTITLEMENTS="$ROOT/$ENTITLEMENTS_ARG" ;;
esac

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi
if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "Entitlements not found: $ENTITLEMENTS" >&2
  exit 1
fi

sign() {
  codesign --force --options runtime --timestamp \
    "${KEYCHAIN_ARG[@]}" \
    --sign "$IDENTITY" \
    "$@"
}

FRAMEWORKS="$APP_PATH/Contents/Frameworks"
SPARKLE="$FRAMEWORKS/Sparkle.framework"

# Sparkle (Direct build) carries nested code bundles and helper executables. They
# must be re-signed inside-out, BEFORE the framework wrapper that seals them — a
# plain `find -type f` over the framework would sign bundle internals as loose
# files and break the signature / notarization.
if [[ -d "$SPARKLE" ]]; then
  V="$SPARKLE/Versions/B"
  for nested in \
    "$V/XPCServices/Downloader.xpc" \
    "$V/XPCServices/Installer.xpc" \
    "$V/Updater.app" \
    "$V/Autoupdate"; do
    [[ -e "$nested" ]] && sign "$nested"
  done
  sign "$SPARKLE"
fi

# Any other embedded frameworks / loose dylibs (none today; defensive for the
# future). Each .framework is signed as a bundle; loose dylibs individually.
if [[ -d "$FRAMEWORKS" ]]; then
  for fw in "$FRAMEWORKS"/*.framework; do
    [[ -d "$fw" && "$fw" != "$SPARKLE" ]] || continue
    sign "$fw"
  done
  while IFS= read -r -d '' dylib; do
    sign "$dylib"
  done < <(find "$FRAMEWORKS" -maxdepth 1 -type f -name '*.dylib' -print0)
fi

# The app last, with the channel-specific entitlements.
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  "${KEYCHAIN_ARG[@]}" \
  --sign "$IDENTITY" \
  "$APP_PATH"

# Deep verification catches a mis-ordered nested signature before notarization does.
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --verbose=4 "$APP_PATH"
