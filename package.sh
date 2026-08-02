#!/bin/bash
# Packages MultiClock.app into a distributable .dmg with a styled installer window.
#
#   ./package.sh                             build universal, ad-hoc sign, make DMG
#   NOTARY_PROFILE=multiclock ./package.sh   also notarize + staple
#
# Notarization needs an Apple Developer Program membership and a Developer ID
# Application certificate. Store credentials once with:
#
#   xcrun notarytool store-credentials multiclock \
#       --apple-id you@example.com \
#       --team-id TEAMID \
#       --password <app-specific-password>
#
# Without that, the DMG still works, but see the Gatekeeper warning at the end.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MultiClock"
APP_BUNDLE="build/${APP_NAME}.app"
VOL_NAME="${APP_NAME}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG_PATH="build/${APP_NAME}-${VERSION}.dmg"
RW_DMG="build/${APP_NAME}-rw.dmg"

# Where the installer window opens on screen. The window's *size* and the icon
# positions inside it are not set here — they come from geometry.sh, emitted by
# Tools/GenerateDMGBackground.swift, so the arrow and the icons cannot disagree.
WIN_LEFT=200
WIN_TOP=120

# --- Build ---------------------------------------------------------------------
# Universal by default: a distributed build shouldn't exclude Intel Macs.
echo "==> Building universal app"
UNIVERSAL=1 ./build.sh

SIGN_INFO=$(codesign -dv "${APP_BUNDLE}" 2>&1)
IS_ADHOC=0
if grep -q "adhoc" <<<"${SIGN_INFO}"; then
    IS_ADHOC=1
fi

# --- Installer background -------------------------------------------------------
echo "==> Rendering installer background"
BG_DIR="build/dmg-background"
rm -rf "${BG_DIR}"
swift Tools/GenerateDMGBackground.swift "${BG_DIR}" >/dev/null
# A multi-resolution TIFF: Finder maps the background 1:1 to points, so shipping only
# the 2x PNG would double the window size rather than sharpen it.
tiffutil -cathidpicheck "${BG_DIR}/background.png" "${BG_DIR}/background@2x.png" \
    -out "${BG_DIR}/background.tiff" >/dev/null

# The drawing code owns the layout; adopt its numbers rather than repeating them.
# shellcheck source=/dev/null
source "${BG_DIR}/geometry.sh"
: "${DMG_WIN_WIDTH:?geometry.sh did not define the window size}"

# --- Stage ----------------------------------------------------------------------
echo "==> Staging disk image contents"
STAGING="build/dmg-staging"
rm -rf "${STAGING}"
mkdir -p "${STAGING}/.background"

cp -R "${APP_BUNDLE}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"
cp "${BG_DIR}/background.tiff" "${STAGING}/.background/background.tiff"

# --- Writable image, so Finder can record the window layout ----------------------
echo "==> Creating writable image"
rm -f "${RW_DMG}" "${DMG_PATH}"
# Slack on top of the payload: the .DS_Store holding the layout is written after the
# image is sized, and a full volume silently loses it.
SIZE_MB=$(( $(du -sm "${STAGING}" | cut -f1) + 60 ))
hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGING}" \
    -ov \
    -format UDRW \
    -size "${SIZE_MB}m" \
    "${RW_DMG}" >/dev/null

MOUNT_DIR="/Volumes/${VOL_NAME}"
hdiutil attach "${RW_DMG}" -noautoopen >/dev/null
trap 'hdiutil detach "${MOUNT_DIR}" -force >/dev/null 2>&1 || true' EXIT

# --- Style the window -----------------------------------------------------------
echo "==> Applying installer window layout"
STYLED=1
osascript <<EOF >/dev/null 2>&1 || STYLED=0
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {${WIN_LEFT}, ${WIN_TOP}, $((WIN_LEFT + DMG_WIN_WIDTH)), $((WIN_TOP + DMG_WIN_HEIGHT))}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to ${DMG_ICON_SIZE}
        set text size of opts to 12
        set background picture of opts to file ".background:background.tiff"
        set position of item "${APP_NAME}.app" of container window to {${DMG_APP_ICON_X}, ${DMG_ICON_Y}}
        set position of item "Applications" of container window to {${DMG_APPLICATIONS_X}, ${DMG_ICON_Y}}
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

if [[ "${STYLED}" == "0" ]]; then
    echo "    WARNING: Finder styling failed. The DMG is still usable (the app and the"
    echo "             Applications shortcut are both there) but the window will open"
    echo "             unstyled. Grant Terminal permission to control Finder under"
    echo "             System Settings > Privacy & Security > Automation, then re-run."
else
    echo "    layout recorded"
fi

# Mounting read-write leaves this behind; it ships otherwise, hidden but pointless.
rm -rf "${MOUNT_DIR}/.fseventsd"

# Let Finder flush the .DS_Store holding the layout before the volume goes away.
sync
sleep 1
hdiutil detach "${MOUNT_DIR}" >/dev/null 2>&1 || hdiutil detach "${MOUNT_DIR}" -force >/dev/null
trap - EXIT

# --- Compress -------------------------------------------------------------------
echo "==> Compressing"
hdiutil convert "${RW_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}" >/dev/null
rm -f "${RW_DMG}"

# --- Sign / notarize ------------------------------------------------------------
if [[ "${IS_ADHOC}" == "0" ]]; then
    SIGN_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
    echo "==> Signing disk image"
    codesign --force --sign "${SIGN_ID}" --timestamp "${DMG_PATH}"

    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        echo "==> Submitting for notarization (this takes a few minutes)"
        xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
        echo "==> Stapling ticket"
        xcrun stapler staple "${DMG_PATH}"
        xcrun stapler validate "${DMG_PATH}"
    fi
fi

rm -rf "${STAGING}" "${BG_DIR}"

echo ""
echo "==> Done: ${DMG_PATH}"
du -h "${DMG_PATH}" | sed 's/^/    /'
echo ""

if [[ "${IS_ADHOC}" == "1" ]]; then
    cat <<'WARNING'
    ────────────────────────────────────────────────────────────────────
    WARNING: this build is ad-hoc signed, not notarized.

    It runs fine on THIS Mac. But once someone downloads the DMG, macOS
    sets a quarantine flag and Gatekeeper will refuse to open the app —
    typically with "MultiClock is damaged and can't be opened."

    That is Gatekeeper, not a corrupt file. Recipients can bypass it:

        xattr -dr com.apple.quarantine /Applications/MultiClock.app

    For a DMG anyone can open normally, you need an Apple Developer
    Program membership ($99/yr), a Developer ID Application certificate,
    and notarization. See the header of this script.
    ────────────────────────────────────────────────────────────────────
WARNING
fi
