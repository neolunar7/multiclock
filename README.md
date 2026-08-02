# MultiClock

A macOS menu bar app showing multiple time zones at once — one compact menu bar item
that opens a dropdown listing every configured clock.

Built as a replacement for running several copies of [Second Clock](https://sindresorhus.com/second-clock),
which supports only one additional time zone per instance.

```
menu bar:  ⌁  NY 10:23   🔋 84%  ⌘
              └───┬───┘
                click ↓
         ┌────────────────────────┐
         │ New York   10:23  Sat  │
         │ San Fran.  07:23  Sat  │
         │ Seoul      23:23  Sat+1│
         └────────────────────────┘
```

## Features

- One menu bar item, any number of clocks in the dropdown
- Per-clock custom label, drag to reorder
- The clock at the top of the list is the one shown in the menu bar — reordering is
  how you change it, so there's no separate setting to keep in sync with the order
- Day-offset badge (`+1` / `−1`) when a zone is on a different calendar day
- Relative offset from your local zone ("13h ahead"), which is the number you
  actually need when scheduling a call
- 12/24-hour, optional seconds (menu bar and dropdown independently)
- Launch at login via `SMAppService`
- Settings window with a searchable time zone picker

## Build

Requires the Swift toolchain. Full Xcode is **not** needed — Command Line Tools is
enough, which is why the `.app` bundle is assembled by `build.sh` rather than
`xcodebuild`.

```sh
./build.sh
open build/MultiClock.app
```

To install:

```sh
cp -R build/MultiClock.app /Applications/
```

A debug build:

```sh
CONFIG=debug ./build.sh
```

## Distributing

```sh
./package.sh          # -> build/MultiClock-1.0.dmg
```

This builds a universal (arm64 + x86_64) binary, assembles the app, and produces a
DMG with the usual drag-to-Applications layout.

**A DMG alone is not enough for other people to run it.** macOS attaches a quarantine
flag to anything downloaded, and Gatekeeper refuses to open apps that aren't signed
with a Developer ID *and* notarized by Apple — usually reporting the app as "damaged",
which is misleading, since nothing is wrong with the file.

Two ways forward:

**Informal sharing.** Ship the ad-hoc DMG and tell recipients to run:

```sh
xattr -dr com.apple.quarantine /Applications/MultiClock.app
```

Fine for colleagues, unacceptable for strangers — you're asking them to disable a
security check on your say-so.

**Proper distribution.** Requires an [Apple Developer Program](https://developer.apple.com/programs/)
membership ($99/yr) and a Developer ID Application certificate. Once the certificate
is in your keychain, `build.sh` picks it up automatically and switches on the hardened
runtime. Store notarization credentials once:

```sh
xcrun notarytool store-credentials multiclock \
    --apple-id you@example.com \
    --team-id TEAMID \
    --password <app-specific-password>
```

Then:

```sh
NOTARY_PROFILE=multiclock ./package.sh
```

which signs, submits to Apple, waits for the result, and staples the ticket to the DMG
so it validates even offline. `notarytool` and `stapler` both ship with Command Line
Tools, so full Xcode still isn't needed.

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/MultiClock/MultiClockApp.swift` | `@main`, wires up the `MenuBarExtra` and `Settings` scenes |
| `Sources/MultiClock/Models/Clock.swift` | The clock value type |
| `Sources/MultiClock/Models/ClockStore.swift` | Clocks + preferences, persisted to `UserDefaults` |
| `Sources/MultiClock/Support/Ticker.swift` | Boundary-aligned clock tick |
| `Sources/MultiClock/Support/TimeFormatting.swift` | Cached formatters, day-offset math |
| `Sources/MultiClock/Views/MenuBarLabel.swift` | The compact menu bar item |
| `Sources/MultiClock/Views/ClockListView.swift` | The dropdown panel |
| `Sources/MultiClock/Views/SettingsView.swift` | Settings window and time zone picker |
| `Tools/GenerateIcon.swift` | Draws the app icon and writes the `.iconset` |
| `Resources/Info.plist` | Bundle metadata; `LSUIElement` makes it menu-bar-only |
| `build.sh` | Compiles and assembles the `.app` |
| `package.sh` | Builds universal, makes the `.dmg`, optionally notarizes |

## The icon

The icon is drawn in code (`Tools/GenerateIcon.swift`) rather than committed as a
binary asset, so it stays diffable and each size renders natively instead of being
downsampled from one master. `build.sh` regenerates it when the drawing code changes.

Detail is dropped deliberately as sizes shrink — hour ticks below 128pt, the secondary
ring below 32pt, and at 16pt the remaining face recentres and grows to use the space
the ring would have occupied.

To iterate on it:

```sh
swift Tools/GenerateIcon.swift Resources/AppIcon.iconset
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
open Resources/AppIcon.iconset/icon_512x512.png
```

## Notes

- `ClockStore` and `Ticker` are singletons rather than SwiftUI environment objects.
  The `MenuBarExtra` label renders in its own hosting context, where environment
  objects injected at the `Scene` level don't reliably reach it.
- The ticker runs at 60s resolution and only drops to 1s when something on screen
  actually displays seconds.
- The build is ad-hoc signed. That's enough to run locally and for `SMAppService` to
  register launch-at-login, but distributing it would need a Developer ID.
