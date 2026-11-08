# Focus reading and native audio sources

## Reader

- Reading controls and status bar start hidden. A center tap toggles controls; edge taps turn pages using Readium's DirectionalNavigationAdapter. The underlying text remains selectable and links retain Readium behavior.
- Controls are overlays, not a navigation bar that repeatedly changes EPUB pagination. The progress footer does not intercept page taps.
- ReaderPaper supplies identical background/text colors to EPUB preferences, the native viewport, the surrounding screen, progress footer and reading controls. Reader-only light/dark/sepia/OLED does not rewrite the application theme.
- A page-turn animation setting controls Readium's animated tap/keyboard navigation; Reduce Motion overrides it. Vertical scrolling does not use page-turn animation. This is a smooth sliding transition, not a simulated paper curl.
- New once-only focus-reading hint explains center taps, edge taps and text selection. All new interface copy is RU/EN.
- readerPageAnimation participates in settings backup/restore.

API references checked against Readium 3.11.1: docs/Guides/Navigator/Input.md, DirectionalNavigationAdapter.swift, EPUBPreferences.swift and Navigator/Preferences/Types.swift in https://github.com/readium/swift-toolkit.

## Native audio source additions

Книга в ухе and Аудиокниги Клуб are now selectable AudioSource values and appear alongside LibriVox/Internet Archive in Search, settings and library shortcuts. Search reads public catalog pages; up to three pages are combined with stable URL-based book IDs. Catalog-specific new/popular/genre pages are used for discovery.

Книга в ухе: public page playlist JSON parsed without executing JavaScript. Stable chapter IDs and server order are preserved; signed URLs are refreshed by fetching the book page again, with cached chapter metadata available when offline. Playback/download integration uses the existing player and downloader.

Аудиокниги Клуб: native catalog search and cards are connected. The ordinary anonymous player-token / book-data flow was tested; book-data retrieval returned HTTP 403. The app attempts the normal flow and displays a source-unavailable message plus Open on website when denied. Native playback/download for this source is NOT verified and should not be treated as working. No access-control bypass or token forging is used.

## Live checks, 2026-11-08

- Книга в ухе Любовь query: 30 catalog cards across 3 pages; tested book playlist has 79 entries.
- A sampled MP3 returns HTTP 206, audio/mpeg, 4096 requested bytes with the app User-Agent and no Referer. This verifies reachability, not a complete offline-download cycle.
- Аудиокниги Клуб Любовь query: 36 catalog cards across 3 pages. Player metadata endpoint returns 403.
- Книга в ухе /new/ and /popular/ return 10 parseable cards each. Genre routes taken from /genres/. Аудиокниги Клуб popular route is /index/top/, not /top/. Genre routes taken from /sections/.
- Added tests for HTML title highlights/entities, stable metadata identity, JSON-array extraction with brackets in chapter names, chapter ordering and reader palette. XCTest was not run.
- Swift syntax/localization resource checks passed. No simulator, IPA build, native UI render, installation or end-to-end device test of this update was run.
