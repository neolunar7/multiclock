#!/bin/bash
# Emits the Homebrew cask for the DMG in build/.
#
#   ./Tools/generate-cask.sh <releases-repo> [tag] > multiclock.rb
#
# e.g. ./Tools/generate-cask.sh neolunar7/multiclock-dist v1.0
#
# The cask points at a release asset, which must be publicly downloadable —
# Homebrew does not authenticate. The *source* repository can stay private; only
# the built artifact needs to be reachable.
set -euo pipefail

cd "$(dirname "$0")/.."

REPO="${1:?usage: generate-cask.sh <owner/repo> [tag]}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
TAG="${2:-v${VERSION}}"
DMG="build/MultiClock-${VERSION}.dmg"

if [[ ! -f "${DMG}" ]]; then
    echo "error: ${DMG} not found — run ./package.sh first" >&2
    exit 1
fi

SHA=$(shasum -a 256 "${DMG}" | cut -d' ' -f1)

cat <<EOF
cask "multiclock" do
  version "${VERSION}"
  sha256 "${SHA}"

  url "https://github.com/${REPO}/releases/download/${TAG}/MultiClock-#{version}.dmg"
  name "MultiClock"
  desc "Menu bar clock showing multiple time zones at once"
  homepage "https://github.com/${REPO}"

  app "MultiClock.app"

  # Everything the app writes, so 'brew uninstall --zap' leaves nothing behind.
  zap trash: [
    "~/Library/Preferences/com.neolunar7.multiclock.plist",
    "~/Library/Saved Application State/com.neolunar7.multiclock.savedState",
  ]

  caveats <<~CAVEATS
    MultiClock is not notarized by Apple. If macOS reports it as damaged,
    install with --no-quarantine, or clear the flag manually:

      xattr -dr com.apple.quarantine "\$(brew --prefix)/Caskroom/multiclock"
  CAVEATS
end
EOF
