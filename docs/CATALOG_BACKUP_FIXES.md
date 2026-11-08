# File backup and catalog fixes

## Backup

iCloud folder connection and automatic synchronization have been removed from the application flow. Google Drive remains. Local export creates a ZIP containing library.json plus EPUB files named by UUID. Import validates schema, duplicates, entry types, individual and total uncompressed sizes, and EPUB containers before merging. Backup tombstones do not delete current books; explicitly restored books can override local deletion tombstones. UI confirms restore before applying it. Settings, reading progress and named bookmarks are included; audio files are explicitly excluded from this backup format. Native export/import needs physical-device verification.

## Catalogs

LibriVox discovery previously fetched 50 newest projects and then filtered by language, often producing no Russian results. It now searches the LibriVox collection via the Internet Archive index, with language filtering on the server. Other Archive audio uses its broader catalog. Genre queries include multiple catalog terms, especially romance/novel and Russian variants. Array-valued language/author metadata is accepted. Popularity uses download ordering, new arrivals use publicdate ordering. For you retains preference-based ranking.

Open Library general discovery no longer silently restricts all results to classics/adventure. New books are limited to first publication in the current and previous two calendar years. Missing edition covers no longer discard otherwise valid matching editions. Publication metadata is catalog-supplied and can contain mistakes.

## Verification on 2026-11-08

- 14 live public audio API cases: Russian/English, title, author, genre and feed ordering.
- Russian Archive collection query: 449 total records; romance query: 2 matching records.
- Russian LibriVox API title/author queries returned 404; English Pride and Prejudice returned 2 recordings.
- Corrected Open Library parsing: 33 candidate Russian recent books, 60 English, 24 Russian popular. App displays at most 24.
- Romance book: 75 MP3 files; first file returned HTTP 206 and audio/mpeg for a 4096-byte range request.
- Scripts in scripts/test_audio_sources.py and scripts/test_catalog_fixes.py can reproduce public API tests. They test upstream APIs, not an installed iPhone app.
- Swift syntax and RU/EN key/placeholder checks passed. No IPA build or simulator. Native UI/file restore and XCTest remain unverified.

## Alternatives reviewed

Loyal Books lists 64 Russian books and overlaps the existing public-domain catalog: https://www.loyalbooks.com/language/Russian
AudiobookDB describes a metadata catalog; public app integration requires a written agreement: https://audiobookdb.org/docs
LitRes provides partner catalog and download-link APIs with partner authentication: https://docs.litres.ru/public/205502033.html

No additional provider is enabled without a tested integration.
