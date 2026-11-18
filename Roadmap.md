## Roadmap

Planned for upcoming versions. Order and contents may change; suggestions are welcome as GitHub issues.

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

### Known issues

- Rarely (about once per full UI-test batch, never on its own), Select on the first Home album right after launch does nothing, even with focus on it. One cause was fixed in 1.11. The UI tests now record a screenshot and the element tree when it happens.
