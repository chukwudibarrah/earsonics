## 1.03: Navigation & structure

* Reworked the tab bar to text-only items (dropped icons), with a dedicated magnifying-glass Search tab.
* Flattened navigation so albums/artists push cleanly instead of nesting.
* Reordered Album detail so the action buttons (Play/Shuffle/Star) sit above the artwork.
* Shuffle now scoped to the current list rather than the whole library.
* Song rows made self-contained, and lazy-fetching of album/track detail so lists load faster.
* Hid track numbers in list views outside of an album context.

## 1.04: Layout overhaul, theming & playback fixes

* New layout architecture: the now-playing mini-player is now a system safe-area inset, so content shifts smoothly when playback starts/stops instead of jumping. Centralized spacing (AppLayout) for consistent padding across every screen.
* Custom highlight colour: new Appearance setting lets you pick an accent (orange, red, pink, purple, blue, teal, green, yellow) that drives focus outlines, the now-playing glow, and play/pause indicators.
* Accent focus rings: cards and rows draw a consistent accent outline + soft glow when focused (no more system magnification jitter).
* Marquee text: long titles/artist names scroll while focused instead of just truncating.
* Richer Home screen shelves: Just arrived, Keep spinning, Recently played, Discover.
* Playback fixes: fixed artist→album navigation, fixed a double-skip when a track ended, and moved audio-session setup off the main thread for smoother UI.

## 1.05: Home text polish

* Fixed clipped album/track text on the Home screen — descenders (e.g. the "g"/"y" in titles) were being cut off by fixed-height frames.
* Home cards now use the same focus-driven marquee scrolling for titles that don't fit.

## 1.06: Offline caching, selectable quality & connection reliability

* **Cache played songs for offline replay.** Tracks now download to disk as they stream and are served from cache on replay, with a configurable size cap (1–10 GB, LRU eviction) and a Clear cache action in Settings. A track is only cached once it's played all the way through — skipped or interrupted plays are never partially cached.
* **Selectable stream quality.** Choose Original (lossless), MP3 320 kbps, or MP3 192 kbps from Settings — the same setting drives both live playback and what gets cached, so a replayed track always matches its first play.
* **Passwords moved to the Keychain.** Server passwords are no longer stored in plain text in UserDefaults; existing servers are migrated automatically on first launch.
* **Fixed intermittent failures to load an album's tracks or cover art**, especially noticeable after the app had been idle for a while. Network requests now hedge against dead pooled connections — a slow or stalled request is raced against a fresh one rather than just timed out, so first-open failures that used to require backing out and reopening now resolve on their own, typically within a few seconds. A "Couldn't load tracks" screen with a Retry button now covers the rare case where the server is genuinely unreachable, instead of an empty screen.
* Servers screen restyled to match the rest of the app (card rows instead of a plain list).
* Home screen loads faster: the artist list (which can be slow on large libraries) is no longer fetched as part of Home, and playlists are now fetched once and shared across shelves instead of once per shelf.

## 1.07: Clearer Home errors & rebuilt server editor

* When the library can't be loaded — for example the active server is unreachable or returns an error — Home now shows a clear "Couldn't load your library" message that names the active server, along with a Retry button and a reminder to check the server (or switch servers) in Settings, instead of a silent blank screen.
* Rebuilt the Add/Edit server screen. It's now a single screen (no separate detail step), with clean full-width fields instead of a grouped form — fixing the "field inside a field" look — and Save and Delete return you to the servers list. This also removes the grouped-form text-field machinery implicated in a freeze when opening the server editor on tvOS, and cuts the navigation depth to reach it.