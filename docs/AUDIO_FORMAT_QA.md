# Dark Reader 0.5.0 - Audio, import and UX QA

## API research sources

- LibriVox official: https://librivox.org/api/info
  - Search endpoint: \`/api/feed/audiobooks/?title=...&format=json&limit=20&coverart=1\`
  - Chapters: \`/api/feed/audiotracks/?project_id=...&format=json\`
  - Since September 2026, maximum limit is 500. Dark Reader uses 20.
- Internet Archive: https://archive.org/developers/index-apis.html
  - Search via \`/advancedsearch.php\` and JSON \`/metadata/{identifier}\`
  - Only items in audiobook-related subjects / collections are queried; actual MP3 files are checked before playback.
- GitHub Actions \`Check audiobook APIs\` performs live HTTP smoke tests. Metadata and API schema inspection alone are not a successful live download test.

## Manual checks on iPhone

1. Open Audio tab, search LibriVox for a known public-domain title. Open a record and verify chapters, stream playback, pause/next, position on re-open, speed and lock screen controls.
2. Change source to Internet Archive and repeat. Files that lack an MP3 must show a clear empty-chapters message.
3. Cancel a running search. Change source while searching. Old results must not overwrite the new view.
4. Import a valid EPUB, FB2, classic DRM-free MOBI and ZIP containing each. A bad ZIP, DRM MOBI or unsupported compression should show an understandable warning.
5. Add two named OPDS catalogs in Settings with HTTPS URLs and different query parameter names. Verify both appear in the selector and use the configured values.
6. Search a slow catalog with and without VPN. The Cancel button must always work. A slow-query suggestion should appear without an alert.
7. Search for books, open a card, view cover and description if available, download, then open it from Library.
8. Set "Fantasy" in Genres and verify "For you" uses actual catalog results with book covers rather than author-only chips.
9. In "Support project", verify only currency ticker labels and a centered wallet address, accurate copy action, and the USDT network picker.
10. Test portrait, landscape, light/dark appearance and localization at default and large Dynamic Type sizes.
11. Restore older libraries after an upgrade. Local library data is not deleted during this code rebuild.

## Important limitations

- This release converts FB2 and classic PalmDOC MOBI to EPUB. Some formatting/images can be lost.
- No Google Drive sync or cloud backup of downloaded audio in this build.
- Neither Apple simulators nor API smoke checks can confirm end-to-end iCloud upload after a real re-sign.
