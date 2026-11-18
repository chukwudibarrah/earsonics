## Roadmap

Planned for upcoming versions. Order and contents may change; suggestions are welcome as GitHub issues.

### 1.11: Navigation, volume and genres (Apple TV)

- Up reaches the Now Playing button from the top of any page, wherever focus is. Today it only works from items directly below it, on the right, and not at all from the Play and Shuffle buttons on Tracks.
- Investigate a Select press on a Home album being ignored about a second after launch: seen once in four UI-test runs, perhaps while Home's shelves were still updating.
- More even volume: use the Replay Gain values Navidrome and other OpenSubsonic servers report, with a choice of track or album gain (album keeps an album's own loud and quiet songs; track evens out shuffles). Tracks without Replay Gain tags currently play unadjusted. Either measure them on the device or add a guide to tagging the library once on the server.
- Genres in the sidebar: every genre with its song and album counts, each with Play, Shuffle and its albums. Genre mixes carry on with more from the same genre when they end. Built in the shared core, so the iPhone and iPad app gets it too.

### 2.0: iPhone and iPad

A new app on the same App Store listing as the Apple TV app (universal purchase).

- Touch interface: a tab bar on iPhone, a sidebar on iPad, a mini player, and a full Now Playing screen with the queue and lyrics.
- AirPlay: an output picker, including AirPlay 2 multi-room and HomePod.
- Lock Screen and Control Center controls with artwork; playback continues when the phone locks.
- Downloads: save albums and playlists for offline listening.
- A separate stream quality for mobile data and Wi-Fi.
- Queue editing: remove, play next and reorder.

### 2.1: CarPlay

- Browse recently played music, playlists, albums, artists and downloads in the car, with CarPlay's Now Playing screen.
- Uses the same queue and downloads as the iPhone app, so offline music plays without signal.
- Depends on Apple granting the CarPlay audio entitlement.

### 3.0: Mac

- A native Mac app with the iPad layout, menu bar commands, keyboard shortcuts and media keys.
- AirPlay from the Mac.

### Features for every platform, as they're ready

- "Go to artist" / "Go to album" from Now Playing and album pages.
- An artist's top songs, and song "radio".
- Correct timing for synced lyrics that include an offset.
- A Top Shelf extension on Apple TV showing recently played and newly added music.
