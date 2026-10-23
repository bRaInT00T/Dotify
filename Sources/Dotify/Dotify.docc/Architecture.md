# Architecture

How Dotify is put together.

## Overview

Dotify is a single Swift Package Manager executable built with SwiftUI and AppKit. It has three windows and two ways
of talking to Spotify.

```
            ┌──────────────── AppModel (shared state) ────────────────┐
            │                                                          │
  Spotify desktop app ◀─AppleScript─ SpotifyController ─▶ PanelController ─▶ player window
                                          │
                                          └─track changes─▶ LibraryStore ─▶ search window
                                                               ▲
  Spotify Web API ◀── SpotifyAPI ◀── SpotifyAuth (PKCE)        │
                         ▲                                     │
                         └──────────────── DeviceStore ─▶ speaker window
                                              ▲
                     CoreAudio · IOBluetooth · Bonjour
```

## Playback: AppleScript

``SpotifyController`` polls the Spotify desktop app once a second through ``ScriptRunner``. It also refreshes
immediately when Spotify posts its `com.spotify.client.PlaybackStateChanged` distributed notification. Scripts run on
one serial queue and are compiled once.

Between polls, the playback position is interpolated locally so progress bars move smoothly. After a local change,
such as seeking or changing volume, polled values are ignored for a moment so the UI doesn't snap back.

Commands such as play/pause, next, seek, volume, shuffle and `play track <uri>` are one-line AppleScript calls. The
controller checks whether Spotify is running first, because addressing it would otherwise launch it.

## Web API: sign-in and requests

``SpotifyAuth`` implements Authorization Code with PKCE. ``LoopbackServer`` accepts exactly one `/callback` request on
`127.0.0.1:43821` using Network.framework. The refresh token lives in the Keychain via ``Keychain``. Access tokens are
kept in memory and refreshed on demand, with concurrent callers sharing one refresh.

``SpotifyAPI`` is a thin client that retries once after a 401 with a fresh token, and maps Spotify's JSON into
``MediaItem`` and ``ConnectDevice``.

## Search and history

``LibraryStore`` owns the query, the multi-select ``MediaKind`` filters, debounced search results and Recently Played.
Recently Played merges Spotify's history with a local history that ``SpotifyController`` feeds through its
`onTrackChange` callback. The local history is the only source of podcast episodes.

## Speakers

``DeviceStore`` combines four sources:

- ``AudioOutputs``: CoreAudio outputs and the default output device, with a listener for changes.
- ``BluetoothAudio``: paired audio-class devices from IOBluetooth, connected with `openConnection()`.
- ``AirPlayBrowser``: `_airplay._tcp` and `_sonos._tcp` Bonjour browsing, to list AirPlay receivers and label Sonos rooms.
- ``SpotifyAPI``: Spotify Connect devices and playback transfer.

## Player window

``PanelController`` owns the borderless, non-activating ``PlayerPanel``. It reacts to ``Preferences`` and
``PanelState`` (hover, focus, toolbar):

- It resizes for layout changes, keeping the top-left corner fixed.
- It adds or removes the toolbar strip using ``PanelGeometry``. The strip goes on the top edge, or the bottom if there's
  no room above, and is removed from the same edge, so the player never drifts.
- It fades the window to the idle opacity when the player is neither hovered nor focused.
- It handles keyboard shortcuts.

``RootView`` picks the layout view and stacks ``PlayerToolbar`` on the correct edge.

## Persistence

| Where | What |
|---|---|
| UserDefaults (`local.dotify`) | Layout, opacity, idle opacity, toggles, panel position, window frames, Client ID, granted scopes, filters, local history |
| Keychain (service `local.dotify`) | Spotify refresh token |

## Testing

`swift test` covers the loopback callback server, history merging and filters, CoreAudio output listing, and the
toolbar frame math. Tests use a separate Keychain service so they never touch the real sign-in.

For visual checks, `DOTIFY_SNAPSHOT_DIR=/some/dir` makes the app render every layout (collapsed and expanded), the
search window and the speaker window to PNGs, write the Spotify Connect and AirPlay device lists to `devices.txt`, and
quit. Launch it with `open` so permission prompts are attributed to Dotify:

```sh
open -W --env DOTIFY_SNAPSHOT_DIR=/tmp/snaps build/Dotify.app
```
