# Connecting Spotify

Enable search, full listening history and Spotify Connect speakers.

## Overview

Playback works without connecting. Search, Spotify's listening history and Spotify Connect use the Spotify Web API,
which requires a Spotify developer app that you own.

## Create a developer app

1. Open the [Spotify developer dashboard](https://developer.spotify.com/dashboard) and create an app.
2. Under **Which API/SDKs are you planning to use?**, tick only **Web API**.
3. Add the redirect URI `http://127.0.0.1:43821/callback` exactly. Spotify doesn't accept `localhost`.
4. Copy the app's **Client ID**.

## Connect Dotify

1. Press **F** to open Search, then type anything. The setup form appears.

   ![The Connect Spotify form: steps to create a developer app, the redirect URI with a copy button, and a Client ID field.](search-connect)

2. Paste the Client ID and click **Connect**.
3. Approve in your browser. The tab says Dotify is connected.

Dotify uses the Authorization Code flow with PKCE, so there's no client secret. During sign-in it listens on
`127.0.0.1:43821` for the browser's redirect, then stops listening. The refresh token is saved in your login Keychain.

## Permissions requested

| Scope | Used for |
|---|---|
| `user-read-recently-played` | Recently Played |
| `user-read-playback-state` | Listing Spotify Connect devices |
| `user-modify-playback-state` | Moving playback between devices and setting device volume |

Sign-ins made before speaker control existed lack the playback scopes. The speaker picker shows a **Reconnect**
button in that case.

## Spotify's limits

These are Spotify's Development Mode rules, not Dotify's:

- The developer app's owner needs **Spotify Premium**.
- Search returns at most **10 results per type**.
- Spotify's history API doesn't include podcasts. Dotify keeps its own local history of everything it sees play,
  which covers podcast episodes played while Dotify was running.
- Sonos speakers usually don't appear in Spotify's device list. See <doc:ChoosingSpeakers>.

## Disconnect

Choose **Disconnect Spotify Account** from the menu. Dotify deletes the saved sign-in from the Keychain.
