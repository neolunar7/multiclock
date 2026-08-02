#!/bin/bash
# Builds MultiClock.app.
#
# SwiftPM only produces a bare executable, so the .app bundle is assembled by hand.
# That's the whole reason this script exists instead of `xcodebuild` — this machine
# has Command Line Tools, not full Xcode.
#
#   ./build.sh                 native arch, ad-hoc signed (fast, for local use)
#   UNIVERSAL=1 ./build.sh     arm64 + x86_64 (for distributing to other Macs)
#   CONFIG=debug ./build.sh    debug build
#   SIGN_ID="Developer ID Application: You (TEAMID)" ./build.sh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MultiClock"
CONFIG="${CONFIG:-release}"
UNIVERSAL="${UNIVERSAL:-0}"
APP_BUNDLE="build/${APP_NAME}.app"

# Prefer a real Developer ID if one exists; fall back to ad-hoc ("-").
# Ad-hoc runs locally but Gatekeeper rejects it once a download sets the
# quarantine bit — see package.sh.
if [[ -z "${SIGN_ID:-}" ]]; then
    # `|| true` matters: grep exits 1 when there's no Developer ID, and under
    # `set -e` a failing command substitution would abort the whole script.
    SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" \
        | head -1 \
        | sed -E 's/.*"(.*)"/\1/' || true)
    SIGN_ID="${SIGN_ID:--}"
fi

# The icon is generated from Tools/GenerateIcon.swift rather than committed, so the
# drawing code is the single source of truth. Regenerated only when missing or stale —
# rendering ten sizes costs a few seconds and rarely changes.
if [[ ! -f "Resources/AppIcon.icns" || "Tools/GenerateIcon.swift" -nt "Resources/AppIcon.icns" ]]; then
    echo "==> Generating app icon"
    swift Tools/GenerateIcon.swift Resources/AppIcon.iconset >/dev/null
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
fi

echo "==> Compiling (${CONFIG})"
if [[ "${UNIVERSAL}" == "1" ]]; then
    # `swift build --arch arm64 --arch x86_64` needs xcbuild from full Xcode, which
    # isn't installed. Building each slice separately and lipo-ing them gets the same
    # universal binary using only Command Line Tools.
    swift build -c "${CONFIG}" --triple arm64-apple-macosx14.0  --scratch-path .build-arm64
    swift build -c "${CONFIG}" --triple x86_64-apple-macosx14.0 --scratch-path .build-x86_64

    mkdir -p ".build/universal"
    lipo -create \
        ".build-arm64/${CONFIG}/${APP_NAME}" \
        ".build-x86_64/${CONFIG}/${APP_NAME}" \
        -output ".build/universal/${APP_NAME}"
    BINARY=".build/universal/${APP_NAME}"
else
    swift build -c "${CONFIG}"
    BINARY=".build/${CONFIG}/${APP_NAME}"
fi

echo "==> Assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BINARY}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

echo "==> Signing as: ${SIGN_ID}"
if [[ "${SIGN_ID}" == "-" ]]; then
    codesign --force --sign - --timestamp=none "${APP_BUNDLE}"
else
    # Hardened runtime and a secure timestamp are both prerequisites for notarization.
    codesign --force --sign "${SIGN_ID}" \
        --options runtime \
        --timestamp \
        "${APP_BUNDLE}"
fi

echo "==> Built ${APP_BUNDLE}"
lipo -info "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" 2>/dev/null | sed 's/^/    /'
echo "    Run:     open ${APP_BUNDLE}"
echo "    Install: cp -R ${APP_BUNDLE} /Applications/"
