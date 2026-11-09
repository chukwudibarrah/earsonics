## Roadmap

Planned for upcoming versions. Order and contents may change; suggestions are welcome as GitHub issues.

**Code health**

- Swift 6 language mode (fix the remaining concurrency warnings in the caching code).
- Move from `ObservableObject`/Combine to `@Observable`, so screens refresh reliably when nested state changes.
- One shared store for playlists and favourites: starring a song in Now Playing updates every list, and playlists are fetched once instead of on six screens.
- A brief message for every action that can fail (star, rename, delete, search) instead of failing silently.
- Accessibility labels on the icon-only buttons (transport controls, hearts, close).
- More unit tests: server URL checks, decoding sample replies from different servers, and the Keychain migration.

**Additional features**

- Queue editing: remove, play next and reorder from the Queue screen.
- "Go to artist" / "Go to album" from Now Playing and album pages.
- Browse by genre, an artist's top songs, and song "radio".
- Correct timing for synced lyrics that include an offset.
- A Top Shelf extension showing recently played and newly added music.
