# Dark Reader: technical specification

## Goal
Create a Russian-language iOS/iPadOS reading application for browsing an OPDS book catalog, searching by title or author, downloading books, reading offline and resuming from the last position.

## Technology
- iOS 17+, SwiftUI, Readium Swift Toolkit 3.11.1, Swift Package Manager.
- Persistent local files in Documents/Books and a JSON index.
- GitHub Actions runner on macOS creates an unsigned IPA for external signing.

## Functional requirements
1. Search books by title and author via configurable HTTPS OPDS or other authorized catalog API.
2. Show title, author, cover, description and available formats.
3. Download books with progress and error handling, prevent duplicate imports and validate file format/size.
4. Read EPUB offline; plan FB2 conversion or native support and PDF support as later milestones.
5. Save precise reading positions for each book automatically, restore on reopening and after app restart.
6. Provide library, sorting, favorites, bookmarks, table of contents, and deletion.
7. Themes: system, light, dark, sepia, true OLED.
8. Typography: font family, size, line spacing, margins; vertical scrolling or page turns.
9. Support imported EPUB files from iOS Files app.
10. Handle unavailable sources and network interruptions gracefully.
11. Keep data local unless user explicitly enables synchronization.
12. Ensure source use complies with copyright and catalog terms. No DRM bypass.

## Acceptance criteria
- iOS device build compiles in GitHub Actions, unsigned IPA uploaded as artifact.
- Test EPUB import, catalog search and download, airplane-mode reading and progress restoration.
- Verify accessibility, Dynamic Type and iPad layout.
- Do not claim availability of the configured catalog without live testing.

## Development stages
1. Compile MVP with Readium, import, local bookshelf, OPDS.
2. Test and fix author/title search, metadata and covers.
3. Improve progress autosave, bookmarks, TOC, typography and OLED.
4. Add FB2/PDF, tests, localization and release QA.

## Status
Starter implementation only, not independently compiled. The IPA must be signed before installation.
