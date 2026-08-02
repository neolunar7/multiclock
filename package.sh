#!/bin/bash
# Packages MultiClock.app into a distributable .dmg.
#
#   ./package.sh                    build universal, ad-hoc sign, make DMG
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

# --- Build ---------------------------------------------------------------------
# Universal by default: a distributed build shouldn't exclude Intel Macs.
echo "==> Building universal app"
UNIVERSAL=1 ./build.sh

# --- Verify the signature we're about to ship -----------------------------------
SIGN_INFO=$(codesign -dv "${APP_BUNDLE}" 2>&1)
IS_ADHOC=0
if grep -q "adhoc" <<<"${SIGN_INFO}"; then
    IS_ADHOC=1
fi

# --- Stage the DMG contents -----------------------------------------------------
echo "==> Staging disk image contents"
STAGING=$(mktemp -d)
trap 'rm -rf "${STAGING}"' EXIT

cp -R "${APP_BUNDLE}" "${STAGING}/"
# The conventional drag-to-install affordance.
ln -s /Applications "${STAGING}/Applications"

# --- Build the DMG --------------------------------------------------------------
echo "==> Creating ${DMG_PATH}"
rm -f "${DMG_PATH}"
hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" >/dev/null

# --- Sign / notarize the DMG ----------------------------------------------------
if [[ "${IS_ADHOC}" == "0" ]]; then
    SIGN_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
    echo "==> Signing disk image"
    codesign --force --sign "${SIGN_ID}" --timestamp "${DMG_PATH}"

    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        echo "==> Submitting for notarization (this takes a few minutes)"
        xcrun notarytool submit "${DMG_PATH}" \
            --keychain-profile "${NOTARY_PROFILE}" \
            --wait

        echo "==> Stapling ticket"
        # Stapling embeds the ticket so the app validates even offline.
        xcrun stapler staple "${DMG_PATH}"
        xcrun stapler validate "${DMG_PATH}"
    fi
fi

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
