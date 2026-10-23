# Getting Started

Install or build Dotify, grant its permissions and start playing.

## Requirements

| | Player & playback | Search, history & Spotify Connect |
|---|---|---|
| macOS 14 Sonoma or later, Apple silicon or Intel | Required | Required |
| Spotify desktop app, installed and signed in | Required | Required |
| Spotify account | Free or Premium | Premium, on the developer app's owner account |
| Free Spotify developer app and its Client ID | Not needed | Required (<doc:ConnectingSpotify>) |

Dotify only drives the desktop app; the Spotify web player won't work. There are no other runtime dependencies.

## Install the prebuilt app

1. Download **Dotify-x.y.z.zip** from the [latest release](https://github.com/bRaInT00T/Dotify/releases/latest)
   and unzip it. It runs on Apple silicon and Intel.
2. Move **Dotify.app** to **Applications** and open it.
3. Dotify isn't notarized by Apple, so the first launch is blocked with "Dotify Not Opened". Click **Done**, open
   **System Settings → Privacy & Security**, and click **Open Anyway** next to *"Dotify" was blocked…*. You only do
   this once. Alternatively, run `xattr -dr com.apple.quarantine /Applications/Dotify.app` in Terminal.

## Build from source

Building needs Xcode 16 or later (or a Swift 5.10+ toolchain). The first build needs internet access, because Swift
Package Manager fetches swift-docc-plugin, which is only used to generate these docs.

```sh
./build-app.sh             # builds build/Dotify.app for this Mac
./build-app.sh --install   # also copies it to /Applications
./build-app.sh --universal # Apple silicon + Intel
open build/Dotify.app
```

`build-app.sh` builds a release binary with Swift Package Manager, wraps it in an app bundle with
`Resources/Info.plist`, and ad-hoc signs it. `make-release.sh` makes the universal zip and checksum for a release.

Run the tests with:

```sh
swift test
```

## Permissions

macOS asks for each of these the first time Dotify needs it:

| Permission | When | Why |
|---|---|---|
| Automation → Spotify | First launch | Read what's playing and control playback |
| Bluetooth | First time the speaker picker opens | List paired speakers and headphones |
| Local Network | First time the speaker picker opens | Find AirPlay and Sonos speakers |
| Keychain access | After connecting Spotify, and after rebuilds | Read the saved Spotify sign-in |

If you denied Automation, re-enable it in System Settings → Privacy & Security → Automation. Dotify is ad-hoc signed,
so macOS may ask for Automation and Keychain access again after each rebuild.

## Spotify in the background

By default Dotify starts Spotify hidden when Dotify launches, and quits Spotify when Dotify quits. Turn either off in
the menu: **Start Spotify Hidden on Launch** and **Quit Spotify When Dotify Quits**.

## Next steps

- <doc:LayoutsAndControls> covers the player.
- <doc:ConnectingSpotify> enables search, history and Spotify Connect speakers.
