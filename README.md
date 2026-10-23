# Dotify

A tiny floating macOS player for Spotify with six layouts, from a one-line ticker to a full card.
It lives in the menu bar (no Dock icon) and drives the Spotify desktop app over AppleScript,
so Spotify itself can stay hidden in the background.

## Documentation

**Read the docs: <https://braint00t.github.io/Dotify/documentation/dotify/>**

Full guides and code reference are in the DocC catalog at `Sources/Dotify/Dotify.docc`, published to `docs/`
(GitHub Pages serves `main` → `/docs`):

- Getting Started: build, permissions, Spotify in the background
- Layouts and Controls: layouts, toolbar, idle dimming, shortcuts
- Connecting Spotify: developer app setup, scopes, Spotify's limits
- Choosing Speakers: Mac outputs, Bluetooth, AirPlay, Spotify Connect, Sonos
- Architecture: how the pieces fit, persistence, testing

Regenerate the site after changing code or articles:

```sh
./generate-docs.sh
```

To browse it locally, serve the parent of a `Dotify` folder that points at `docs/`, then open
`http://localhost:8000/Dotify/documentation/dotify`.

## Build & run

```sh
./build-app.sh            # builds "build/Dotify.app"
./build-app.sh --install  # also copies it to /Applications
open "build/Dotify.app"
```

On first launch macOS asks to let Dotify control Spotify. Click **Allow**. If you denied it,
re-enable it in System Settings → Privacy & Security → Automation. The app is ad-hoc signed, so you
may be asked again after each rebuild.

## Layouts

| Key | Layout    | Size     | For                                              |
|-----|-----------|----------|--------------------------------------------------|
| 1   | Ticker    | 260×26   | One line of text; controls appear on hover       |
| 2   | Pill      | 300×40   | Thumbnail + title; prev/next appear on hover     |
| 3   | Bar       | 420×76   | Art, title, scrubbable progress, transport       |
| 4   | Card      | 280×432  | Full player: shuffle, repeat, times, volume      |
| 5   | Album Art | 220×220  | Just the cover; everything else on hover         |
| 6   | Column    | 64×236   | Vertical strip to park against a screen edge     |

The panel keeps its top-left corner fixed when you switch layouts, and remembers where you left it.

## Quick-access toolbar & idle dimming

Hover the player and a small tab appears on its bottom edge. Click it (or press **E**) and the player grows
slightly to show a toolbar: **speaker picker**, **layout menu**, **search**, and a collapse arrow. The toolbar
closes on its own once the pointer has left the player and it no longer has focus.

When the pointer is elsewhere and the player isn't focused, it fades to the **Dim When Idle** level
(default 50%; change or turn off in the menu). It returns to full opacity on hover or focus.

## Controls

Click the panel first so it has keyboard focus. It won't pull focus away from other apps.

- **Space** play/pause · **← / →** previous/next · **↑ / ↓** volume
- **1–6** switch layout · **E** show/hide toolbar · **D** speakers · **F** search · **S** shuffle · **R** repeat · **T** always-on-top · **A** album-art background
- **Esc** hide the panel (bring it back from the menu bar ♪ icon)
- Drag anywhere that isn't a control to move it. Right-click for the full menu.

Menu bar / right-click menu: layout, opacity, always on top, show on all Spaces, album-art background,
always show controls, start Spotify in the background, show/hide Spotify.

## Search & Recently Played

Press **F** (or **/**) in the player, or pick **Search & Recently Played…** from the menu.

- Type to search Spotify. Results are grouped into Songs, Playlists and Podcasts (shows and episodes).
- Filter chips are multi-select and apply to both search and recents. Option-click a chip to show only that kind.
- **↑ / ↓** move, **Return** plays and closes, clicking a row plays and keeps the window open, **Esc** clears or closes.
- Picking a podcast show plays its newest episode.

Recently Played merges Spotify's history (last 50 songs, plus the playlists they came from) with a local
history of everything Dotify saw play. Spotify's history API doesn't include podcasts, so podcast
recents only cover what played while Dotify was running. Local history works without connecting.

### Connecting (needed for search and Spotify's history)

Spotify's Web API requires your own developer app:

1. Create an app at <https://developer.spotify.com/dashboard>, ticking **Web API**.
2. Add the redirect URI `http://127.0.0.1:43821/callback`.
3. Paste the app's Client ID into Dotify and click **Connect**, then approve in the browser.

Spotify requires the developer app's owner to have Premium (Development Mode rules since Feb 2026),
and search returns at most 10 results per type. The sign-in token is stored in your login Keychain;
macOS may ask to allow access after a rebuild because the app is ad-hoc signed.

## Choosing a speaker

Press **D** in the player, use the speaker button in the Card layout, or pick **Choose Speaker…** from the menu.

- **This Mac**: built-in speakers, connected Bluetooth devices, USB and display audio. Picking one makes it the
  Mac's default output (Spotify follows it) and pulls playback back to this Mac if it was on another device.
  Virtual drivers (BlackHole, Teams, etc.) sit behind **More**.
- **Bluetooth · Not Connected**: paired speakers and headphones that are off or disconnected. Click to connect
  and switch to them.
- **Spotify Connect**: network speakers, TVs, phones and other devices running Spotify. Click to move playback
  there; the active device gets a volume slider. Needs the Spotify connection with speaker permissions
  (Dotify asks you to reconnect once if your sign-in predates this feature) and Spotify Premium.

- **AirPlay**: AirPlay receivers on your network (Sonos speakers are labelled). macOS doesn't let apps pick an
  AirPlay target, so clicking one opens Sound settings, where it's one click under Output. Once chosen it shows
  under This Mac. This is the way to reach Sonos speakers, which Spotify's API usually doesn't list.

## Notes

- Requires the Spotify desktop app (not the web player). By default Dotify starts Spotify hidden when it
  launches and quits Spotify when it quits; turn either off in the menu ("Start Spotify Hidden on Launch",
  "Quit Spotify When Dotify Quits").
- Liking tracks, queue, and search aren't exposed by Spotify's AppleScript interface.
- `DOTIFY_SNAPSHOT_DIR=/tmp/snaps "build/Dotify.app/Contents/MacOS/Dotify"` renders
  every layout to PNG and quits (useful when tweaking designs).
