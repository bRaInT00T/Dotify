# ``Dotify``

A tiny floating Spotify player for macOS with six layouts, search, and speaker switching.

## Overview

![The Card layout playing a song, with album art, progress, transport controls and volume.](layout-card)

Dotify is a menu bar app with no Dock icon. It shows a borderless floating player that you can shrink to a single
line of text or grow into a full card, so Spotify takes as little attention and screen space as you want.

It drives the Spotify desktop app, which stays hidden in the background: playback and now-playing info go through
AppleScript. Search, listening history and Spotify Connect speakers go through the Spotify Web API.

- **Six layouts**: Ticker, Pill, Bar, Card, Album Art and Column, switched with keys 1–6.
- **Quick-access toolbar**: hover, then click the tab on the edge to reveal speaker, layout and search buttons.
- **Idle dimming**: the player fades when you're not using it.
- **Search & Recently Played**: songs, playlists and podcasts, with multi-select filters.
- **Speaker picker**: Mac outputs, Bluetooth speakers, AirPlay receivers and Spotify Connect devices.

## Topics

### Using Dotify

- <doc:GettingStarted>
- <doc:LayoutsAndControls>
- <doc:SearchAndHistory>
- <doc:ConnectingSpotify>
- <doc:ChoosingSpeakers>

### How It Works

- <doc:Architecture>

### Playback

- ``SpotifyController``
- ``Track``
- ``PlaybackState``
- ``ScriptRunner``

### Spotify Web API

- ``SpotifyAuth``
- ``SpotifyAPI``
- ``LoopbackServer``
- ``Keychain``
- ``MediaItem``
- ``MediaKind``
- ``ConnectDevice``

### Search and History

- ``LibraryStore``
- ``LibraryPanelController``
- ``LibraryView``

### Speakers

- ``DeviceStore``
- ``AudioOutputs``
- ``AudioOutput``
- ``BluetoothAudio``
- ``BluetoothSpeaker``
- ``AirPlayBrowser``
- ``AirPlaySpeaker``
- ``DevicePanelController``
- ``DevicesView``

### Player Window

- ``PanelController``
- ``PanelState``
- ``PanelGeometry``
- ``PlayerPanel``
- ``RootView``
- ``PlayerToolbar``
- ``ExpandHandle``

### Settings

- ``Preferences``
- ``PlayerLayout``

### Screenshots

- ``Screenshots``
- ``Demo``
