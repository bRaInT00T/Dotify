# Layouts and Controls

Pick how much screen the player takes, and control it from the keyboard.

## Layouts

| Key | Layout | Size (pt) | Shows |
|---|---|---|---|
| 1 | Ticker | 260×26 | One line of text; controls on hover |
| 2 | Pill | 300×40 | Thumbnail and title; previous/next on hover |
| 3 | Bar | 420×76 | Art, title, scrubbable progress with times, transport |
| 4 | Card | 280×432 | Full player: shuffle, repeat, times, volume, speaker button |
| 5 | Album Art | 220×220 | Just the cover; title, progress, times and controls on hover |
| 6 | Column | 64×236 | Vertical strip for a screen edge |

Switching layouts keeps the player's top-left corner fixed. Dotify remembers where you left the player.

## Quick-access toolbar

Hover the player and a small tab appears on its top edge. Click it, or press **E**, and the player grows upward to
show a toolbar:

- **Speaker**: opens the speaker picker (<doc:ChoosingSpeakers>).
- **Layouts**: a menu of all six layouts.
- **Search**: opens Search & Recently Played.
- **Collapse arrow**: hides the toolbar.

The player itself doesn't move. If it's pressed against the top of the screen, the toolbar opens below it instead.
The toolbar closes on its own about a second after the pointer leaves, unless the player has keyboard focus.

## Idle dimming

When the pointer is elsewhere and the player isn't focused, it fades to the **Dim When Idle** level: Off, 70%, 50%
(default), 30% or 15%. It returns to the **Opacity** setting on hover or focus.

## Keyboard shortcuts

Click the player first so it has focus. It doesn't steal focus from other apps.

| Key | Action |
|---|---|
| Space | Play/pause |
| ← / → | Previous/next track |
| ↑ / ↓ | Volume |
| 1–6 | Switch layout |
| E | Show/hide toolbar |
| D | Speaker picker |
| F or / | Search & Recently Played |
| S / R | Shuffle / repeat |
| T | Always on top |
| A | Album-art background |
| Esc | Hide the player |

## Menu options

The ♪ menu bar icon and the player's right-click menu share these options:

- Layout, Opacity, Dim When Idle
- Show Mini Player, Always on Top, Show on All Spaces
- Album Art Background, Always Show Controls
- Start Spotify Hidden on Launch, Quit Spotify When Dotify Quits
- Search & Recently Played, Choose Speaker, Disconnect Spotify Account
