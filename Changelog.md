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

## 1.05: Home text polish (this session)

* Fixed clipped album/track text on the Home screen — descenders (e.g. the "g"/"y" in titles) were being cut off by fixed-height frames.
* Home cards now use the same focus-driven marquee scrolling for titles that don't fit.