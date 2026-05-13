#!/usr/bin/env bash
#
# Build a polished installer DMG: a 540×360 window in icon view, with Sonance.app on the
# left and a shortcut to /Applications on the right, sidebar and toolbar hidden so the
# user sees the standard "drag to install" layout.
#
# The script does the layout dance through AppleScript on a temporary read-write DMG, then
# converts the result to a compressed read-only UDZO image. It is self-contained — no
# create-dmg / dmgbuild dependency — so CI does not need anything beyond hdiutil and
# osascript, which ship with macOS.
#
# Usage: make-dmg.sh /path/to/Sonance.app build/Sonance-v0.3.1.dmg

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 /path/to/Sonance.app /path/to/output.dmg" >&2
  exit 1
fi

APP_PATH="$1"
DMG_PATH="$2"
VOLNAME="${VOLNAME:-Sonance}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

APP_NAME="$(basename "$APP_PATH")"
DMG_DIR="$(cd "$(dirname "$DMG_PATH")" && pwd)"
DMG_NAME="$(basename "$DMG_PATH")"
mkdir -p "$DMG_DIR"
DMG_FULL_PATH="$DMG_DIR/$DMG_NAME"

# Staging area for the source files that will become the DMG's contents.
STAGE="$(mktemp -d)"
TMP_DMG="$(mktemp -u).dmg"
cleanup() {
  # Unmount any of our test mounts that survived an error before tearing down the stage.
  if [[ -n "${MOUNT_DEV:-}" ]]; then
    hdiutil detach "$MOUNT_DEV" -quiet -force >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGE"
  rm -f "$TMP_DMG"
}
trap cleanup EXIT

cp -R "$APP_PATH" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"

# Size the scratch DMG generously — the app is universal-fat and we need slack for the
# Finder's metadata writes during the layout step. `hdiutil create -size auto` would be
# tighter but has occasionally failed on CI when the app grew past the auto-computed size
# mid-build, so use an explicit budget that scales with the app.
APP_SIZE_BYTES=$(du -ks "$STAGE" | awk '{ print $1 * 1024 }')
SLACK_BYTES=$((100 * 1024 * 1024))   # 100 MiB
TOTAL_BYTES=$((APP_SIZE_BYTES + SLACK_BYTES))
DMG_SIZE_MB=$(( (TOTAL_BYTES + 1024 * 1024 - 1) / (1024 * 1024) ))

echo "Building scratch DMG (~${DMG_SIZE_MB} MiB)…"
hdiutil create \
  -srcfolder "$STAGE" \
  -volname "$VOLNAME" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -size "${DMG_SIZE_MB}m" \
  "$TMP_DMG" >/dev/null

echo "Mounting scratch DMG…"
MOUNT_INFO=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG")
MOUNT_DEV=$(echo "$MOUNT_INFO" | awk '/^\/dev\// { print $1; exit }')
MOUNT_PATH=$(echo "$MOUNT_INFO" | awk -F'\t' '/Apple_HFS/ { print $3 }')

if [[ -z "$MOUNT_PATH" ]]; then
  echo "Failed to determine mount path from: $MOUNT_INFO" >&2
  exit 1
fi

# macOS appends " 1", " 2", … to the volume name if another volume of the same name is
# already mounted (e.g. a previously-installed Sonance DMG the user has open). Always
# target the AppleScript at the actual mounted name rather than the requested `$VOLNAME`,
# otherwise the layout silently fails to attach to *our* volume and the resulting DMG
# ships without an arranged Finder window.
ACTUAL_VOL_NAME="$(basename "$MOUNT_PATH")"
echo "Mounted as '$ACTUAL_VOL_NAME' at $MOUNT_PATH (device $MOUNT_DEV)"

# Let the kernel settle the mount before we hit it with AppleScript; Finder occasionally
# returns "AppleEvent timed out" if osascript runs before the volume registers.
sleep 1

echo "Setting Finder window layout via AppleScript…"
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$ACTUAL_VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set sidebar width of container window to 0
        set the bounds of container window to {200, 120, 740, 480}
        set vo to icon view options of container window
        set arrangement of vo to not arranged
        set icon size of vo to 128
        set text size of vo to 13
        set label position of vo to bottom
        set position of item "$APP_NAME" of container window to {140, 180}
        set position of item "Applications" of container window to {400, 180}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT

# Persist the layout. Finder writes .DS_Store asynchronously; without the sync the layout
# can fail to stick on the compressed image.
sync
sleep 1

echo "Detaching scratch DMG…"
hdiutil detach "$MOUNT_DEV" -quiet >/dev/null
MOUNT_DEV=""

echo "Compressing to final DMG: $DMG_FULL_PATH"
rm -f "$DMG_FULL_PATH"
hdiutil convert "$TMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_FULL_PATH" >/dev/null

echo "Verifying DMG…"
hdiutil verify "$DMG_FULL_PATH" >/dev/null
echo "Done: $DMG_FULL_PATH"
ls -lh "$DMG_FULL_PATH"
