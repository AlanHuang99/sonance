#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 /path/to/Sonance.app 'Developer ID Application: ...' [keychain]" >&2
  exit 1
fi

APP_PATH="$1"
IDENTITY="$2"
KEYCHAIN_ARG=()
if [[ $# -ge 3 && -n "${3:-}" ]]; then
  KEYCHAIN_ARG=(--keychain "$3")
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT/Sonance/Sonance.entitlements"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
  while IFS= read -r -d '' item; do
    codesign --force --options runtime --timestamp \
      "${KEYCHAIN_ARG[@]}" \
      --sign "$IDENTITY" \
      "$item"
  done < <(find "$APP_PATH/Contents/Frameworks" -type f -perm -111 -print0)
fi

codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  "${KEYCHAIN_ARG[@]}" \
  --sign "$IDENTITY" \
  "$APP_PATH"

codesign --verify --strict --verbose=2 "$APP_PATH"
codesign --display --verbose=4 "$APP_PATH"
