# Apple Watch page-turn remote

This branch adds a direct BLE path from an Apple Watch Series 9 to an Xteink X4
running CrossPoint. No iPhone or external bridge is used after the watch app is
installed.

## Protocol

- Device name: `X4 Watch Remote`
- Service: `F8A10001-7B4A-4C8B-9C61-4B5D6A731001`
- Command characteristic (write): `F8A10002-7B4A-4C8B-9C61-4B5D6A731001`
- Reader state characteristic (read/notify): `F8A10003-7B4A-4C8B-9C61-4B5D6A731001`
- Book title characteristic (read): `F8A10004-7B4A-4C8B-9C61-4B5D6A731001`
- `0x01`: next page
- `0x02`: previous page

The NimBLE callback only places commands in a small protected queue. CrossPoint's
main loop drains the queue and emits its normal `PageForward` or `PageBack` logical
button edge.

Reader state is a versioned 16-byte little-endian payload so notifications fit
inside the default 20-byte ATT value limit:

| Offset | Size | Value |
| --- | ---: | --- |
| 0 | 1 | Protocol version (`1`) |
| 1 | 1 | Reader type (`0` none, `1` EPUB, `2` TXT, `3` XTC) |
| 2 | 1 | Flags (bit 0 means a reader is active) |
| 3 | 1 | Whole-book progress, `0...100` |
| 4 | 1 | X4 battery, `0...100` |
| 5 | 1 | Reserved |
| 6 | 4 | Current page, 1-based |
| 10 | 4 | Page total (chapter for EPUB, book for TXT/XTC) |
| 14 | 2 | Book-title revision token |

The watch reads the UTF-8 title characteristic when the revision changes. This
keeps routine page notifications compact while still supporting long titles.

## Build the watch app

The checked-in Xcode project is generated from `watch-app/project.yml` using
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cd watch-app
xcodegen generate
open X4WatchTurner.xcodeproj
```

Select your development team, connect the Series 9, and run the app. The deployment
target is watchOS 11 because `handGestureShortcut(.primaryAction)` is what maps
Double Tap to the Next Page button.

## Build the firmware

The helper script installs CrossPoint's pinned pioarduino Core into a local virtual
environment, builds the X3/X4 firmware, and copies the binary into `dist/`:

```sh
./scripts/build-watch-remote.sh
```

Flash `dist/x4-watch-turner-firmware.bin` as a custom X4 binary using CrossPoint's
web flasher. Keep a stock or known-good CrossPoint binary available for recovery.

## Use it

1. Flash the custom CrossPoint firmware.
2. Open a book and enable Bluetooth in CrossPoint.
3. Open **X4 Turner** on the watch.
4. Wait for **X4 connected**.
5. Double Tap to advance. The Previous button remains available as an ordinary tap.
6. Swipe vertically for the live book and reading-session pages.

The three Watch pages are:

- **Remote** — next/previous controls, connection state, and feedback settings.
- **Book** — title, whole-book progress, page position, format, and X4 battery.
- **Session** — elapsed time, forward/back remote turns, and pages-per-hour pace.

The watch app must remain visible for the Double Tap primary action to fire.

## Current prototype constraints

- The command characteristic is intentionally simple and does not yet require an
  encrypted write. Nearby devices would need to know the private service UUID, but a
  bonding-only mode should be added before broader distribution.
- The firmware is based on CrossPoint's experimental `feat-bluetooth` branch. That
  branch already operates close to the X4's memory limits, so on-device heap and
  reconnect testing is required before calling this stable.
- Session turn counts describe commands sent from this Watch app. Physical X4
  button presses and commands from other remotes are not yet included.
