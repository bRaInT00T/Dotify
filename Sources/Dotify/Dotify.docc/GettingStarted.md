# Getting Started

Build Dotify, grant its permissions and start playing.

## Requirements

- macOS 14 or later
- Xcode 16 or later, or the matching Swift toolchain
- The Spotify desktop app (not the web player)

## Build and run

```sh
./build-app.sh            # builds build/Dotify.app
./build-app.sh --install  # also copies it to /Applications
open build/Dotify.app
```

`build-app.sh` builds a release binary with Swift Package Manager, wraps it in an app bundle with
`Resources/Info.plist`, and ad-hoc signs it.

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
