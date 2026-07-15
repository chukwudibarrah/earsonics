# About earsonics

earsonics is a native tvOS app for listening to your own music library on the big screen, through a Subsonic-compatible server you host yourself.

## Why it exists

Most music apps assume you want someone else's catalogue and someone else's subscription. earsonics assumes the opposite: you already have a library — ripped CDs, purchased files, a lifetime of downloads — sitting on a server you run (Navidrome, Airsonic, Gonic, or anything else that speaks the Subsonic API), and you just want a good way to play it on an Apple TV. No account, no subscription, no telemetry, no algorithmic feed you didn't ask for. You point it at your server, and it plays your music.

## What it is (and isn't)

- It **is** a client. It renders and plays whatever your Subsonic server serves it — nothing more.
- It **is not** a music source, a streaming service, or a store. earsonics does not host, index, license, or distribute any music itself.
- It **is not** affiliated with, endorsed by, or connected to the Subsonic project, Navidrome, Airsonic, Apple, or any streaming service. "Subsonic" refers to the open API standard the app speaks, not a company relationship.
- Everything the app does — libraries, playback, artwork, playlists, caching — depends entirely on the server you configure it against and what you've chosen to put on it.

## Who's responsible for what

You are responsible for the server you connect earsonics to and the content on it, including making sure you have the rights to whatever you store there and stream through it. earsonics itself is just the player. See [`terms-and-conditions.md`](terms-and-conditions.md) for the full terms.

## Tech

Built with SwiftUI for tvOS, talking to your server over the [Subsonic REST API](http://www.subsonic.org/pages/api.jsp). No backend of its own, no analytics, no third-party SDKs. Source is available under the MIT license — see [`LICENSE`](LICENSE) — and contributions are welcome (see the [README](README.md#contributing)).

## Author

Built and maintained by [Chukwudi Barrah](https://github.com/chukwudibarrah).
