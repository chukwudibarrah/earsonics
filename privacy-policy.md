# earsonics privacy policy

Last updated: 9 November 2026

## Overview

earsonics is an Apple TV app for listening to your own music through a Navidrome or other Subsonic-compatible server that you run. This policy explains what earsonics stores, what it sends and where, and what it never does.

In short: earsonics has no account system, no backend of its own, and no analytics. The only place it ever sends data is the server you add to it.

## What earsonics does not collect

earsonics does not collect, store or share any of the following, with us or with anyone else:

- Personal information (name, email address, phone number)
- Location data
- Device identifiers or advertising identifiers
- Usage analytics or crash reports
- Behavioural or tracking data of any kind
- Payment information

earsonics contains no third-party SDKs, analytics frameworks, advertising networks or tracking libraries. The source code is public, so you can check this yourself.

## What is stored on your Apple TV

earsonics keeps the following on your Apple TV only.

**Server details.** The name, address and username of each server you add are kept in the app's settings storage. Passwords are kept separately in the Apple TV's Keychain. They are encrypted by the system, never written to the app's settings, and never included in backups or synced to other devices.

**Preferences.** Your playback and display choices. These include stream quality, crossfade, volume normalisation, screen-saver behaviour, highlight colour, cache size, and what happens when a queue ends or the app opens.

**Caches.** To make the app faster and to replay music without streaming it again, earsonics keeps:

- copies of songs you've played
- cover art
- a copy of your current play queue (the songs in it and how far into the current song you were), saved separately for each server

Caches are kept in the system's cache storage, which tvOS may clear when space runs low. You can empty the song and artwork caches at any time in Settings. Removing a server deletes its password and its saved queue. Deleting the app removes everything above.

## What is sent to your server

earsonics talks directly to the server address you enter, and to nothing else. It sends:

- **Sign-in details.** Your username, and a one-time token made from your password and a random value. Your password itself is never sent.
- **Library requests.** Requests to browse and search your library (artists, albums, songs, playlists, favourites, genres and lyrics), and to stream audio and cover art.
- **Changes you make.** Starring and un-starring, and creating, renaming, editing or deleting playlists.
- **Listening activity, sent as scrobbles:**
  - When a song starts, earsonics tells your server what's playing.
  - Once you've listened to half a song (or four minutes, if that comes first), it records the song as played.
- **Your play queue, if "Sync queue with server" is on (it is by default).** The songs in your queue and your position are saved to your server, so you can pick up where you left off in other Subsonic apps or on another Apple TV. Turn this off in Settings → Queue to keep your queue on this Apple TV only.
- **Autoplay requests, if you turn autoplay on.** When a queue ends and you've chosen to keep the music going, earsonics asks your server for songs to play next: similar songs, more by the same artist, similar artists, the same genre, or random songs.
- **The app's name.** Every request identifies the app as "earsonics", so your server may list it as the player you're using.

What your server does with this information is up to the server and how you've set it up. Some servers, for example, use services such as Last.fm to suggest similar songs or to share your listening history. earsonics never contacts those services itself.

We never see any of this data. earsonics is only a client: it talks to your server, not ours.

## Apple TV system features

Like other music apps, earsonics shares the current song's title, artist, album and cover art with tvOS. This shows what's playing in Control Center and lets the Siri Remote and other remotes control playback. This information stays within Apple's system features on your device.

## Third-party services

earsonics has no third-party services built in. Settings includes an optional "buy me a coffee" QR code. It's a picture stored inside the app: scanning it with your phone opens a PayPal page on your phone. earsonics itself never connects to PayPal and never handles payments.

## Children's privacy

earsonics doesn't collect personal information from anyone, including children.

## Security

Use an `https://` address for your server wherever you can, especially if you connect over the internet. Over plain `http://`, your music and the sign-in token in each request travel unencrypted, and someone on the same network path could reuse the token to access your server.

To help with this:

- tvOS blocks plain `http://` connections to most internet domain names.
- earsonics shows a warning when you add a server that would connect without encryption.
- Plain `http://` is generally fine for servers on your home network, such as a local IP address or a `.local` name.

earsonics never writes your password or sign-in tokens to logs.

## Changes to this policy

If this policy changes, the updated version will be published here with a new "Last updated" date. The project's full change history is public on GitHub.

## Contact

Questions about this policy or earsonics: earsonics@willproseforfood.com
